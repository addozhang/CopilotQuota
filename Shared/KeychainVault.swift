import Foundation
import Security
import os

private let vaultLog = Logger(subsystem: "app.solocraft.quotaring", category: "vault")

/// Secret material stored per `ProviderAccount` in the macOS Keychain.
/// Never written to `UserDefaults` and never accessed by the Widget extension.
public enum ProviderSecret: Codable, Equatable, Sendable {
    case oauth(StoredCredentials)
    case apiKey(String)
}

/// Protocol for per-account credential storage (Keychain in production, in-memory in tests).
public protocol CredentialVaulting: Sendable {
    func load(accountID: UUID) -> ProviderSecret?
    @discardableResult
    func save(_ secret: ProviderSecret, for accountID: UUID) -> Bool
    func delete(accountID: UUID)
}

/// Host-app-only macOS Keychain vault keyed by `ProviderAccount.id`.
public final class KeychainVault: CredentialVaulting, @unchecked Sendable {
    public static let defaultService = "app.solocraft.quotaring"
    public let service: String

    public init(service: String = KeychainVault.defaultService) {
        self.service = service
    }

    private func query(for accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "account.\(accountID.uuidString)",
        ]
    }

    public func load(accountID: UUID) -> ProviderSecret? {
        var q = query(for: accountID)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                vaultLog.error("Vault read failed (OSStatus \(status, privacy: .public))")
            }
            return nil
        }
        return try? JSONDecoder().decode(ProviderSecret.self, from: data)
    }

    @discardableResult
    public func save(_ secret: ProviderSecret, for accountID: UUID) -> Bool {
        guard let data = try? JSONEncoder().encode(secret) else { return false }
        let base = query(for: accountID)

        let updateStatus = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            SecItemDelete(base as CFDictionary)
        }

        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "QuotaRing Provider Credential"
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            vaultLog.error("Vault add failed (OSStatus \(status, privacy: .public))")
            return false
        }
        return true
    }

    public func delete(accountID: UUID) {
        let status = SecItemDelete(query(for: accountID) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            vaultLog.error("Vault delete failed (OSStatus \(status, privacy: .public))")
        }
    }
}

/// Thread-safe in-memory vault for unit tests.
public final class InMemoryCredentialVault: CredentialVaulting, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UUID: ProviderSecret] = [:]

    public init(initial: [UUID: ProviderSecret] = [:]) {
        self.storage = initial
    }

    public func load(accountID: UUID) -> ProviderSecret? {
        lock.lock()
        defer { lock.unlock() }
        return storage[accountID]
    }

    @discardableResult
    public func save(_ secret: ProviderSecret, for accountID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        storage[accountID] = secret
        return true
    }

    public func delete(accountID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: accountID)
    }
}

/// One-time migration from Copilot Quota v1.x (`app.solocraft.copilotquota`) to QuotaRing v2.0.
enum LegacyV1Migration {
    private static let legacySuiteName = "app.solocraft.copilotquota"

    @discardableResult
    static func migrateIfNeeded(
        store: SharedSnapshotStore,
        vault: CredentialVaulting,
        legacyDefaults: UserDefaults? = UserDefaults(suiteName: legacySuiteName),
        legacyCredentialStore: CredentialStoring = KeychainCredentialStore()
    ) -> Bool {
        guard !store.v1MigrationCompleted else { return false }
        store.v1MigrationCompleted = true

        // Carry over preferences if set in v1.x.
        if let legacyDefaults {
            let interval = legacyDefaults.integer(forKey: "refreshIntervalMinutes")
            if [5, 10, 30, 60].contains(interval) {
                store.refreshIntervalMinutes = interval
            }
            if legacyDefaults.object(forKey: "showDockIcon") != nil {
                store.showDockIcon = legacyDefaults.bool(forKey: "showDockIcon")
            }
        }

        // Skip credential migration if accounts already exist.
        guard store.accounts.isEmpty else { return false }

        // Read legacy Copilot OAuth credentials from v1.4 Keychain or v1.3 UserDefaults.
        let legacyCreds: StoredCredentials? = legacyCredentialStore.load()
            ?? readPlaintextLegacyCreds(from: legacyDefaults)

        guard let creds = legacyCreds, !creds.accessToken.isEmpty else {
            return false
        }

        let account = ProviderAccount(kind: .copilot, sortOrder: 0)
        guard vault.save(.oauth(creds), for: account.id) else {
            return false
        }
        store.accounts = [account]

        // Convert cached v1.x QuotaDisplay into a v2.0 ProviderSnapshot for instant rendering.
        if let data = legacyDefaults?.data(forKey: "cachedDisplay"),
           let oldDisplay = try? JSONDecoder().decode(QuotaDisplay.self, from: data) {
            let snapshot = ProviderSnapshot(
                accountID: account.id,
                kind: .copilot,
                accountLabel: oldDisplay.login,
                planLabel: oldDisplay.planLabel,
                metric: .metered(
                    percentRemaining: oldDisplay.percentRemaining,
                    remaining: oldDisplay.primaryRemaining ?? oldDisplay.premium?.remaining,
                    entitlement: oldDisplay.primaryEntitlement ?? oldDisplay.premium?.entitlement,
                    resetAt: QuotaDisplay.parseResetDate(oldDisplay.resetDate),
                    unlimited: oldDisplay.isPrimaryUnlimited
                ),
                fetchedAt: oldDisplay.fetchedAt
            )
            store.upsertSnapshot(snapshot)
        }
        return true
    }

    private static func readPlaintextLegacyCreds(from defaults: UserDefaults?) -> StoredCredentials? {
        guard let defaults,
              let raw = defaults.string(forKey: "githubToken")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        let refresh = defaults.string(forKey: "githubRefreshToken")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let expiry = defaults.object(forKey: "githubTokenExpiresAt") as? Date
        return StoredCredentials(
            accessToken: raw,
            refreshToken: (refresh?.isEmpty == false) ? refresh : nil,
            expiresAt: expiry
        )
    }
}
