import Foundation

/// Decodes a JSON number or numeric string (e.g. `"98"` or `98`) into a `Double`.
struct FlexibleDouble: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let d = try? container.decode(Double.self) {
            self.value = d
            return
        }
        if let s = try? container.decode(String.self),
           let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            self.value = d
            return
        }
        throw DecodingError.typeMismatch(
            Double.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Double or numeric String")
        )
    }
}

struct KimiUsageResponse: Decodable {
    struct User: Decodable {
        struct Membership: Decodable {
            let level: String?
        }
        let membership: Membership?
    }

    struct QuotaDetail: Decodable {
        let limit: FlexibleDouble?
        let used: FlexibleDouble?
        let remaining: FlexibleDouble?
        let resetTime: String?
    }

    struct WindowSpec: Decodable {
        let duration: Int?
        let timeUnit: String?
    }

    struct RateLimitItem: Decodable {
        let window: WindowSpec?
        let detail: QuotaDetail?
    }

    let user: User?
    let usage: QuotaDetail?
    let limits: [RateLimitItem]?
}

/// Kimi Code (Coding Plan) provider (`GET https://api.kimi.com/coding/v1/usages`).
struct KimiProvider: QuotaProvider {
    let kind: ProviderKind = .kimi
    static let usageURL = URL(string: "https://api.kimi.com/coding/v1/usages")!

    func fetchSnapshot(account: ProviderAccount, vault: CredentialVaulting) async throws -> ProviderSnapshot {
        guard case .apiKey(let apiKey) = vault.load(accountID: account.id), !apiKey.isEmpty else {
            throw ProviderError.missingCredentials
        }

        var request = URLRequest(url: Self.resolvedUsageURL())
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("QuotaRing/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            let decoded = try JSONDecoder().decode(KimiUsageResponse.self, from: data)
            return try Self.map(response: decoded, account: account)
        case 401, 403:
            throw ProviderError.unauthorized
        default:
            throw ProviderError.http(status)
        }
    }

    static func map(response: KimiUsageResponse, account: ProviderAccount, now: Date = .now) throws -> ProviderSnapshot {
        var windows: [QuotaWindow] = []

        // Short-term rolling windows first (e.g. 300 minutes -> 5h).
        if let limits = response.limits {
            for (idx, item) in limits.enumerated() {
                guard let detail = item.detail, let remainingPct = remainingPercent(from: detail) else {
                    continue
                }
                let (id, label) = windowLabel(for: item.window, index: idx)
                let resetAt = detail.resetTime.flatMap(parseISO8601)
                windows.append(QuotaWindow(id: id, label: label, percentRemaining: remainingPct, resetAt: resetAt))
            }
        }

        // Top-level weekly quota second (7d) so Dual Ring displays [5h, 7d].
        if let weekly = response.usage, let remainingPct = remainingPercent(from: weekly) {
            let resetAt = weekly.resetTime.flatMap(parseISO8601)
            windows.append(QuotaWindow(id: "7d", label: "7d", percentRemaining: remainingPct, resetAt: resetAt))
        }

        guard !windows.isEmpty else {
            throw ProviderError.invalidResponse(L("Kimi Code returned no quota information."))
        }

        let plan: String?
        if let rawLevel = response.user?.membership?.level, !rawLevel.isEmpty {
            let cleaned = rawLevel
                .replacingOccurrences(of: "LEVEL_", with: "", options: [.caseInsensitive, .anchored])
                .replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            plan = cleaned.isEmpty ? nil : cleaned.capitalized
        } else {
            plan = nil
        }

        return ProviderSnapshot(
            accountID: account.id,
            kind: .kimi,
            accountLabel: account.displayName,
            planLabel: plan,
            metric: .rollingWindows(windows),
            fetchedAt: now
        )
    }

    private static func remainingPercent(from detail: KimiUsageResponse.QuotaDetail) -> Double? {
        if let limit = detail.limit?.value, limit > 0 {
            if let remaining = detail.remaining?.value {
                return min(100, max(0, (remaining / limit) * 100.0))
            }
            if let used = detail.used?.value {
                return min(100, max(0, ((limit - used) / limit) * 100.0))
            }
        }
        if let remaining = detail.remaining?.value {
            return min(100, max(0, remaining))
        }
        if let used = detail.used?.value {
            return min(100, max(0, 100.0 - used))
        }
        return nil
    }

    private static func windowLabel(for spec: KimiUsageResponse.WindowSpec?, index: Int) -> (String, String) {
        if let duration = spec?.duration, duration > 0 {
            let unit = (spec?.timeUnit ?? "").uppercased()
            if unit.contains("MINUTE") {
                if duration % 60 == 0 {
                    let hours = duration / 60
                    return ("\(hours)h-\(index)", "\(hours)h")
                }
                return ("\(duration)m-\(index)", "\(duration)m")
            }
            if unit.contains("HOUR") {
                return ("\(duration)h-\(index)", "\(duration)h")
            }
            if unit.contains("DAY") {
                return ("\(duration)d-\(index)", "\(duration)d")
            }
            if unit.contains("WEEK") {
                return ("\(duration)w-\(index)", duration == 1 ? "7d" : "\(duration)w")
            }
        }
        return ("5h-\(index)", index == 0 ? "5h" : "W\(index + 1)")
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: raw) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: raw)
    }

    private static func resolvedUsageURL() -> URL {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["QUOTARING_KIMI_URL"],
           let override = URL(string: raw) {
            return override
        }
        #endif
        return Self.usageURL
    }
}
