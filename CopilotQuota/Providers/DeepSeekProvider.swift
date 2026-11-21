import Foundation

struct DeepSeekBalanceResponse: Decodable {
    struct BalanceInfo: Decodable {
        let currency: String
        let totalBalance: String
        let grantedBalance: String?
        let toppedUpBalance: String?

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case grantedBalance = "granted_balance"
            case toppedUpBalance = "topped_up_balance"
        }
    }

    let isAvailable: Bool
    let balanceInfos: [BalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

/// DeepSeek prepaid balance provider (`GET https://api.deepseek.com/user/balance`).
struct DeepSeekProvider: QuotaProvider {
    let kind: ProviderKind = .deepseek
    static let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!

    func fetchSnapshot(account: ProviderAccount, vault: CredentialVaulting) async throws -> ProviderSnapshot {
        guard case .apiKey(let apiKey) = vault.load(accountID: account.id), !apiKey.isEmpty else {
            throw ProviderError.missingCredentials
        }

        var request = URLRequest(url: Self.balanceURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
            return try Self.map(response: decoded, account: account)
        case 401, 403:
            throw ProviderError.unauthorized
        default:
            throw ProviderError.http(status)
        }
    }

    static func map(response: DeepSeekBalanceResponse, account: ProviderAccount, now: Date = .now) throws -> ProviderSnapshot {
        // Prefer CNY if present with positive balance, otherwise first non-zero, otherwise first entry.
        let chosen = response.balanceInfos.first(where: { $0.currency.uppercased() == "CNY" && (Double($0.totalBalance) ?? 0) > 0 })
            ?? response.balanceInfos.first(where: { (Double($0.totalBalance) ?? 0) > 0 })
            ?? response.balanceInfos.first

        guard let info = chosen, let total = Double(info.totalBalance) else {
            throw ProviderError.invalidResponse(L("DeepSeek returned no balance information."))
        }

        return ProviderSnapshot(
            accountID: account.id,
            kind: .deepseek,
            accountLabel: account.displayName,
            planLabel: "API Balance",
            metric: .balance(
                amount: total,
                currency: info.currency,
                granted: info.grantedBalance.flatMap(Double.init),
                toppedUp: info.toppedUpBalance.flatMap(Double.init)
            ),
            fetchedAt: now
        )
    }
}
