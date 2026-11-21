import Foundation

struct OpenRouterCreditsResponse: Decodable {
    struct Payload: Decodable {
        let totalCredits: Double
        let totalUsage: Double

        enum CodingKeys: String, CodingKey {
            case totalCredits = "total_credits"
            case totalUsage = "total_usage"
        }
    }

    let data: Payload
}

/// OpenRouter prepaid credits provider (`GET https://openrouter.ai/api/v1/credits`).
struct OpenRouterProvider: QuotaProvider {
    let kind: ProviderKind = .openrouter
    static let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!

    func fetchSnapshot(account: ProviderAccount, vault: CredentialVaulting) async throws -> ProviderSnapshot {
        guard case .apiKey(let apiKey) = vault.load(accountID: account.id), !apiKey.isEmpty else {
            throw ProviderError.missingCredentials
        }

        var request = URLRequest(url: Self.creditsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            let decoded = try JSONDecoder().decode(OpenRouterCreditsResponse.self, from: data)
            return Self.map(response: decoded, account: account)
        case 401, 403:
            throw ProviderError.unauthorized
        default:
            throw ProviderError.http(status)
        }
    }

    static func map(response: OpenRouterCreditsResponse, account: ProviderAccount, now: Date = .now) -> ProviderSnapshot {
        let remaining = max(0, response.data.totalCredits - response.data.totalUsage)
        return ProviderSnapshot(
            accountID: account.id,
            kind: .openrouter,
            accountLabel: account.displayName,
            planLabel: "Credits",
            metric: .balance(
                amount: remaining,
                currency: "USD",
                granted: nil,
                toppedUp: response.data.totalCredits
            ),
            fetchedAt: now
        )
    }
}
