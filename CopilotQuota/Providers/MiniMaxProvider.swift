import Foundation

struct MiniMaxRemainsResponse: Decodable {
    struct BaseResp: Decodable {
        let statusCode: Int?
        let statusMsg: String?

        enum CodingKeys: String, CodingKey {
            case statusCode = "status_code"
            case statusMsg = "status_msg"
        }
    }

    struct ModelRemain: Decodable {
        let modelName: String?
        let currentIntervalTotalCount: Double?
        /// Note: MiniMax names this `*_usage_count`, but the API returns the REMAINING count.
        let currentIntervalUsageCount: Double?
        let currentIntervalRemainingPercent: Double?
        let startTime: Double?
        let endTime: Double?
        let remainsTime: Double?

        let currentWeeklyTotalCount: Double?
        /// Note: MiniMax names this `*_usage_count`, but the API returns the REMAINING count.
        let currentWeeklyUsageCount: Double?
        let currentWeeklyRemainingPercent: Double?
        let weeklyStartTime: Double?
        let weeklyEndTime: Double?
        let weeklyRemainsTime: Double?

        enum CodingKeys: String, CodingKey {
            case modelName = "model_name"
            case currentIntervalTotalCount = "current_interval_total_count"
            case currentIntervalUsageCount = "current_interval_usage_count"
            case currentIntervalRemainingPercent = "current_interval_remaining_percent"
            case startTime = "start_time"
            case endTime = "end_time"
            case remainsTime = "remains_time"
            case currentWeeklyTotalCount = "current_weekly_total_count"
            case currentWeeklyUsageCount = "current_weekly_usage_count"
            case currentWeeklyRemainingPercent = "current_weekly_remaining_percent"
            case weeklyStartTime = "weekly_start_time"
            case weeklyEndTime = "weekly_end_time"
            case weeklyRemainsTime = "weekly_remains_time"
        }
    }

    let baseResp: BaseResp?
    let modelRemains: [ModelRemain]?

    enum CodingKeys: String, CodingKey {
        case baseResp = "base_resp"
        case modelRemains = "model_remains"
    }
}

/// MiniMax Coding Plan / Token Plan provider supporting both China (`api.minimaxi.com`)
/// and Global (`api.minimax.io`) endpoints with 5h + 7d rolling windows.
struct MiniMaxProvider: QuotaProvider {
    let kind: ProviderKind = .minimax

    func fetchSnapshot(account: ProviderAccount, vault: CredentialVaulting) async throws -> ProviderSnapshot {
        guard case .apiKey(let apiKey) = vault.load(accountID: account.id), !apiKey.isEmpty else {
            throw ProviderError.missingCredentials
        }

        let region = account.minimaxRegion
        let urls = Self.resolvedURLs(for: region)
        let (data, status) = try await performRequest(url: urls.primary, apiKey: apiKey)

        // Fall back to `/v1/token_plan/remains` if the legacy openplatform route returns 404 or an API error.
        let shouldFallback: Bool
        if status == 404 {
            shouldFallback = true
        } else if status == 200,
                  let decoded = try? JSONDecoder().decode(MiniMaxRemainsResponse.self, from: data),
                  let code = decoded.baseResp?.statusCode,
                  code != 0 {
            shouldFallback = true
        } else {
            shouldFallback = false
        }

        let finalData: Data
        let finalStatus: Int
        if shouldFallback {
            let (fbData, fbStatus) = try await performRequest(url: urls.fallback, apiKey: apiKey)
            if fbStatus == 200 {
                (finalData, finalStatus) = (fbData, fbStatus)
            } else {
                (finalData, finalStatus) = (data, status)
            }
        } else {
            (finalData, finalStatus) = (data, status)
        }

        switch finalStatus {
        case 200:
            let decoded = try JSONDecoder().decode(MiniMaxRemainsResponse.self, from: finalData)
            return try Self.map(response: decoded, account: account)
        case 401, 403:
            throw ProviderError.unauthorized
        default:
            throw ProviderError.http(finalStatus)
        }
    }

    private func performRequest(url: URL, apiKey: String) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        let authValue = apiKey.lowercased().hasPrefix("bearer ") ? apiKey : "Bearer \(apiKey)"
        request.setValue(authValue, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }

    static func map(response: MiniMaxRemainsResponse, account: ProviderAccount, now: Date = .now) throws -> ProviderSnapshot {
        if let code = response.baseResp?.statusCode, code != 0 {
            if code == 1004 {
                throw ProviderError.unauthorized
            }
            let msg = response.baseResp?.statusMsg?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ProviderError.invalidResponse(
                (msg?.isEmpty == false) ? msg! : L("MiniMax API returned an error.")
            )
        }

        guard let remains = response.modelRemains, !remains.isEmpty else {
            throw ProviderError.invalidResponse(L("MiniMax returned no quota information."))
        }

        // Prefer the primary MiniMax-M* coding model bucket with positive quota, falling back to first valid entry.
        let chosen = remains.first(where: { item in
            let name = (item.modelName ?? "").lowercased()
            return name.hasPrefix("minimax-m") && hasIntervalQuota(item)
        }) ?? remains.first(where: hasIntervalQuota) ?? remains[0]

        var windows: [QuotaWindow] = []

        if let pct5h = intervalRemainingPercent(for: chosen) {
            let resetAt = resolveResetDate(endTime: chosen.endTime, remainsTime: chosen.remainsTime, now: now)
            windows.append(QuotaWindow(id: "5h", label: "5h", percentRemaining: pct5h, resetAt: resetAt))
        }

        if let pct7d = weeklyRemainingPercent(for: chosen) {
            let resetAt = resolveResetDate(endTime: chosen.weeklyEndTime, remainsTime: chosen.weeklyRemainsTime, now: now)
            windows.append(QuotaWindow(id: "7d", label: "7d", percentRemaining: pct7d, resetAt: resetAt))
        }

        guard !windows.isEmpty else {
            throw ProviderError.invalidResponse(L("MiniMax returned no quota information."))
        }

        let plan: String
        if let model = chosen.modelName?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            plan = model
        } else {
            plan = account.minimaxRegion == .cn ? "MiniMax CN" : "MiniMax Global"
        }

        return ProviderSnapshot(
            accountID: account.id,
            kind: .minimax,
            accountLabel: account.displayName,
            planLabel: plan,
            metric: .rollingWindows(windows),
            fetchedAt: now
        )
    }

    private static func hasIntervalQuota(_ item: MiniMaxRemainsResponse.ModelRemain) -> Bool {
        if let total = item.currentIntervalTotalCount, total > 0 { return true }
        return item.currentIntervalRemainingPercent != nil
    }

    private static func intervalRemainingPercent(for item: MiniMaxRemainsResponse.ModelRemain) -> Double? {
        if let total = item.currentIntervalTotalCount, total > 0,
           let remaining = item.currentIntervalUsageCount {
            return min(100, max(0, (remaining / total) * 100.0))
        }
        if let pct = item.currentIntervalRemainingPercent {
            return min(100, max(0, pct))
        }
        return nil
    }

    private static func weeklyRemainingPercent(for item: MiniMaxRemainsResponse.ModelRemain) -> Double? {
        if let total = item.currentWeeklyTotalCount, total > 0,
           let remaining = item.currentWeeklyUsageCount {
            return min(100, max(0, (remaining / total) * 100.0))
        }
        if let pct = item.currentWeeklyRemainingPercent {
            return min(100, max(0, pct))
        }
        return nil
    }

    private static func resolveResetDate(endTime: Double?, remainsTime: Double?, now: Date) -> Date? {
        if let endTime, endTime > 0 {
            let seconds = endTime > 1_000_000_000_000 ? endTime / 1000.0 : endTime
            return Date(timeIntervalSince1970: seconds)
        }
        if let remainsTime, remainsTime > 0 {
            return now.addingTimeInterval(remainsTime / 1000.0)
        }
        return nil
    }

    private static func resolvedURLs(for region: MiniMaxRegion) -> (primary: URL, fallback: URL) {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        let primary = env["QUOTARING_MINIMAX_URL"].flatMap(URL.init(string:)) ?? region.quotaURL
        let fallback = env["QUOTARING_MINIMAX_FALLBACK_URL"].flatMap(URL.init(string:)) ?? region.fallbackQuotaURL
        return (primary, fallback)
        #else
        return (region.quotaURL, region.fallbackQuotaURL)
        #endif
    }
}
