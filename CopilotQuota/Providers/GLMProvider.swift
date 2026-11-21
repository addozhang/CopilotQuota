import Foundation

struct GLMQuotaResponse: Decodable {
    struct Payload: Decodable {
        let level: String?
        let limits: [LimitItem]?
    }

    struct LimitItem: Decodable {
        let type: String?
        /// Window unit code from BigModel / Z.ai (3 = hours, 5 = days/monthly, 6 = weeks).
        let unit: Int?
        let number: Int?
        /// Used percentage (0–100).
        let percentage: Double?
        let used: Double?
        let total: Double?
        let currentValue: Double?
        let usage: Double?
        let remaining: Double?
        /// Milliseconds since epoch for next reset.
        let nextResetTime: Double?
    }

    let success: Bool?
    let code: Int?
    let msg: String?
    let data: Payload?
}

/// GLM Coding Plan provider supporting both BigModel (`open.bigmodel.cn`) and Z.ai (`api.z.ai`).
struct GLMProvider: QuotaProvider {
    let kind: ProviderKind = .glm

    func fetchSnapshot(account: ProviderAccount, vault: CredentialVaulting) async throws -> ProviderSnapshot {
        guard case .apiKey(let apiKey) = vault.load(accountID: account.id), !apiKey.isEmpty else {
            throw ProviderError.missingCredentials
        }

        let url = account.glmRegion.quotaURL
        let (data, status) = try await performRequest(url: url, authHeader: apiKey)

        // Some GLM endpoints expect raw key, others accept Bearer. Retry once with Bearer on 401.
        let finalData: Data
        let finalStatus: Int
        if status == 401 && !apiKey.lowercased().hasPrefix("bearer ") {
            (finalData, finalStatus) = try await performRequest(url: url, authHeader: "Bearer \(apiKey)")
        } else {
            (finalData, finalStatus) = (data, status)
        }

        switch finalStatus {
        case 200:
            let decoded = try JSONDecoder().decode(GLMQuotaResponse.self, from: finalData)
            if decoded.success == false {
                throw ProviderError.invalidResponse(decoded.msg ?? L("GLM API returned an error."))
            }
            return try Self.map(response: decoded, account: account)
        case 401, 403:
            throw ProviderError.unauthorized
        default:
            throw ProviderError.http(finalStatus)
        }
    }

    private func performRequest(url: URL, authHeader: String) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }

    static func map(response: GLMQuotaResponse, account: ProviderAccount, now: Date = .now) throws -> ProviderSnapshot {
        guard let limits = response.data?.limits, !limits.isEmpty else {
            throw ProviderError.invalidResponse(L("GLM returned no quota limits."))
        }

        // Prefer credit / token quota buckets; ignore auxiliary tool-call limits unless nothing else exists.
        let primaryLimits = limits.filter { item in
            let t = (item.type ?? "").uppercased()
            return t == "TOKENS_LIMIT" || t == "CREDIT_LIMIT" || t.isEmpty
        }
        let chosen = primaryLimits.isEmpty ? limits : primaryLimits

        let windows: [QuotaWindow] = chosen.enumerated().map { idx, item in
            let usedPercent: Double
            if let pct = item.percentage {
                usedPercent = pct
            } else if let used = item.used ?? item.currentValue,
                      let total = item.total ?? item.usage,
                      total > 0 {
                usedPercent = (used / total) * 100.0
            } else {
                usedPercent = 0
            }
            let remainingPercent = min(100, max(0, 100.0 - usedPercent))
            let resetDate = item.nextResetTime.map { ms in
                // Handle both millisecond (> 1e12) and second timestamps.
                Date(timeIntervalSince1970: ms > 1_000_000_000_000 ? ms / 1000.0 : ms)
            }
            let (id, label) = windowLabel(for: item, index: idx)
            return QuotaWindow(id: id, label: label, percentRemaining: remainingPercent, resetAt: resetDate)
        }

        let plan: String
        if let level = response.data?.level, !level.isEmpty {
            plan = "GLM Coding \(level.capitalized)"
        } else {
            plan = account.glmRegion == .cn ? "BigModel Coding" : "Z.ai Coding"
        }

        return ProviderSnapshot(
            accountID: account.id,
            kind: .glm,
            accountLabel: account.displayName,
            planLabel: plan,
            metric: .rollingWindows(windows),
            fetchedAt: now
        )
    }

    private static func windowLabel(for item: GLMQuotaResponse.LimitItem, index: Int) -> (String, String) {
        if let unit = item.unit, let num = item.number, num > 0 {
            switch unit {
            case 3: return ("\(num)h-\(index)", "\(num)h")
            case 5: return ("\(num)d-\(index)", num == 7 ? "7d" : "\(num)d")
            case 6: return ("\(num)w-\(index)", num == 1 ? "7d" : "\(num)w")
            default: break
            }
        }
        let t = (item.type ?? "").uppercased()
        if t == "CREDIT_LIMIT" { return ("credit-\(index)", "Quota") }
        if t == "TOKENS_LIMIT" { return ("tokens-\(index)", index == 0 ? "5h" : "7d") }
        return ("window-\(index)", "W\(index + 1)")
    }
}
