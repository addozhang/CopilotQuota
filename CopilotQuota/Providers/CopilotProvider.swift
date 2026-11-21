import Foundation
import os

private let copilotLog = Logger(subsystem: "app.solocraft.quotaring", category: "copilot")

/// GitHub Copilot provider backed by OAuth Device Flow + rotating refresh token
/// stored in the host app's `KeychainVault`.
struct CopilotProvider: QuotaProvider {
    let kind: ProviderKind = .copilot
    private static let refreshMargin: TimeInterval = 60 * 60

    func fetchSnapshot(account: ProviderAccount, vault: CredentialVaulting) async throws -> ProviderSnapshot {
        guard case .oauth(var creds) = vault.load(accountID: account.id) else {
            throw ProviderError.missingCredentials
        }

        // Proactively rotate ~8h access token 1h before expiry.
        if let expiresAt = creds.expiresAt,
           expiresAt <= Date().addingTimeInterval(Self.refreshMargin),
           let refreshToken = creds.refreshToken {
            creds = try await rotate(refreshToken: refreshToken, accountID: account.id, vault: vault)
        }

        let client = CopilotQuotaClient()
        let response: CopilotUserResponse
        do {
            response = try await client.fetch(token: creds.accessToken)
        } catch QuotaError.unauthorized {
            guard let refreshToken = creds.refreshToken else {
                throw ProviderError.unauthorized
            }
            let refreshed = try await rotate(refreshToken: refreshToken, accountID: account.id, vault: vault)
            response = try await client.fetch(token: refreshed.accessToken)
        }

        guard let display = response.display else {
            throw QuotaError.notFound
        }

        return ProviderSnapshot(
            accountID: account.id,
            kind: .copilot,
            accountLabel: display.login,
            planLabel: display.planLabel,
            metric: .metered(
                percentRemaining: display.percentRemaining,
                remaining: display.primaryRemaining ?? display.premium?.remaining,
                entitlement: display.primaryEntitlement ?? display.premium?.entitlement,
                resetAt: QuotaDisplay.parseResetDate(display.resetDate),
                unlimited: display.isPrimaryUnlimited
            ),
            fetchedAt: .now
        )
    }

    private func rotate(refreshToken: String, accountID: UUID, vault: CredentialVaulting) async throws -> StoredCredentials {
        do {
            let pair = try await GitHubDeviceFlow().refreshTokens(refreshToken: refreshToken)
            let updated = StoredCredentials(
                accessToken: pair.accessToken,
                refreshToken: pair.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(pair.expiresInSeconds))
            )
            vault.save(.oauth(updated), for: accountID)
            copilotLog.info("Rotated Copilot OAuth token for account \(accountID.uuidString, privacy: .public)")
            return updated
        } catch {
            copilotLog.error("Copilot refresh token rejected: \(error.localizedDescription, privacy: .public)")
            throw ProviderError.unauthorized
        }
    }
}
