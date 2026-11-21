import Foundation

enum ProviderError: LocalizedError, Equatable {
    case missingCredentials
    case unauthorized
    case http(Int)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return L("Credentials are missing. Please reconnect this account.")
        case .unauthorized:
            return L("Authentication failed (401). Please check your credentials or sign in again.")
        case .http(let code):
            return L("API request failed (HTTP %d).", code)
        case .invalidResponse(let detail):
            return detail
        }
    }
}

/// Plugin interface implemented by each AI quota provider.
protocol QuotaProvider: Sendable {
    var kind: ProviderKind { get }
    func fetchSnapshot(account: ProviderAccount, vault: CredentialVaulting) async throws -> ProviderSnapshot
}

/// Central registry resolving `ProviderKind` to its `QuotaProvider` implementation.
struct ProviderRegistry: Sendable {
    private let providers: [ProviderKind: any QuotaProvider]

    static let `default` = ProviderRegistry(providers: [
        CopilotProvider(),
        DeepSeekProvider(),
        OpenRouterProvider(),
        GLMProvider(),
    ])

    init(providers: [any QuotaProvider]) {
        var map: [ProviderKind: any QuotaProvider] = [:]
        for p in providers {
            map[p.kind] = p
        }
        self.providers = map
    }

    func provider(for kind: ProviderKind) -> (any QuotaProvider)? {
        providers[kind]
    }
}
