import Foundation

/// Values shared between the host app and the widget extension.
///
/// Non-sensitive state (cached quota, refresh interval, heartbeat, preferences)
/// lives in the shared preference domain `app.solocraft.copilotquota`.
/// Sensitive OAuth credentials (`accessToken`, `refreshToken`, `expiresAt`)
/// are stored atomically in the macOS Keychain via `KeychainCredentialStore`.
enum SharedStore {
    static let suiteName = "app.solocraft.copilotquota"
    /// Pre-rebrand preference domain. Migrated once on first run.
    private static let legacySuiteName = "com.addo.copilotquota"
    private static let legacyMigratedKey = "legacyStoreMigrated"
    private static let keychainMigratedKey = "keychainCredentialsMigrated"

    private static let legacySettingsKeys = ["cachedDisplay", "refreshIntervalMinutes"]
    private static let plaintextCredentialKeys = [
        "githubToken", "githubRefreshToken", "githubTokenExpiresAt",
    ]

    private static var migrationChecked = false
    private static var customDefaults: UserDefaults?
    private static var customLegacyDefaults: UserDefaults?
    static var credentialStore: CredentialStoring = KeychainCredentialStore()

    private static var defaults: UserDefaults {
        migrateIfNeeded()
        return customDefaults ?? UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static var rawDefaults: UserDefaults {
        customDefaults ?? UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static var rawLegacyDefaults: UserDefaults? {
        if let customLegacyDefaults { return customLegacyDefaults }
        return UserDefaults(suiteName: legacySuiteName)
    }

    /// Test hook: inject isolated `UserDefaults` and `CredentialStoring`.
    static func configureForTesting(defaults: UserDefaults,
                                    legacyDefaults: UserDefaults? = nil,
                                    credentialStore: CredentialStoring) {
        self.customDefaults = defaults
        self.customLegacyDefaults = legacyDefaults
        self.credentialStore = credentialStore
        self.migrationChecked = false
    }

    /// Restore production backing stores after tests.
    static func resetToProduction() {
        self.customDefaults = nil
        self.customLegacyDefaults = nil
        self.credentialStore = KeychainCredentialStore()
        self.migrationChecked = false
    }

    /// One-time migrations:
    /// 1. Carry over settings/cache from pre-rebrand `com.addo.copilotquota`.
    /// 2. Move plaintext OAuth credentials from `UserDefaults` into Keychain
    ///    and scrub the plaintext keys from disk.
    static func migrateIfNeeded() {
        guard !migrationChecked else { return }
        migrationChecked = true
        let store = rawDefaults
        let legacy = rawLegacyDefaults

        // 1. Legacy domain settings carry-over.
        if !store.bool(forKey: legacyMigratedKey) {
            store.set(true, forKey: legacyMigratedKey)
            if let legacy {
                for key in legacySettingsKeys {
                    if let value = legacy.object(forKey: key), store.object(forKey: key) == nil {
                        store.set(value, forKey: key)
                    }
                }
            }
        }

        // 2. Plaintext UserDefaults credentials -> Keychain.
        if !store.bool(forKey: keychainMigratedKey) {
            let source = readPlaintextCredentials(from: store)
                ?? legacy.flatMap { readPlaintextCredentials(from: $0) }

            if let source {
                // Only write if Keychain doesn't already have credentials.
                let migrated: Bool
                if credentialStore.load() != nil {
                    migrated = true
                } else {
                    migrated = credentialStore.save(source)
                }
                if migrated {
                    scrubPlaintextCredentials(from: store)
                    if let legacy { scrubPlaintextCredentials(from: legacy) }
                    store.set(true, forKey: keychainMigratedKey)
                }
            } else {
                store.set(true, forKey: keychainMigratedKey)
            }
        }
    }

    private static func readPlaintextCredentials(from defaults: UserDefaults) -> StoredCredentials? {
        let rawToken = defaults.string(forKey: "githubToken")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = rawToken, !token.isEmpty else { return nil }
        let rawRefresh = defaults.string(forKey: "githubRefreshToken")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let refresh = (rawRefresh?.isEmpty == false) ? rawRefresh : nil
        let expiresAt = defaults.object(forKey: "githubTokenExpiresAt") as? Date
        return StoredCredentials(accessToken: token, refreshToken: refresh, expiresAt: expiresAt)
    }

    private static func scrubPlaintextCredentials(from defaults: UserDefaults) {
        for key in plaintextCredentialKeys {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Credentials (Keychain)

    static var credentials: StoredCredentials? {
        get {
            migrateIfNeeded()
            guard let creds = credentialStore.load() else { return nil }
            let trimmed = creds.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return creds
        }
        set {
            migrateIfNeeded()
            if let newValue {
                credentialStore.save(newValue)
            } else {
                credentialStore.clear()
            }
        }
    }

    static var token: String? {
        get {
            let raw = credentials?.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty == false) ? raw : nil
        }
        set {
            if let newValue, !newValue.isEmpty {
                var current = credentials ?? StoredCredentials(accessToken: newValue, refreshToken: nil, expiresAt: nil)
                current.accessToken = newValue
                credentials = current
            } else {
                clearCredentials()
            }
        }
    }

    /// OAuth refresh token (`ghr_…`). GitHub rotates it on every refresh —
    /// each refresh response returns a NEW refresh token and invalidates the
    /// old one, so both values must be persisted together, atomically.
    static var refreshToken: String? {
        get {
            let raw = credentials?.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty == false) ? raw : nil
        }
        set {
            guard var current = credentials else { return }
            current.refreshToken = (newValue?.isEmpty == false) ? newValue : nil
            credentials = current
        }
    }

    /// When the current access token expires (nil = unknown, legacy login).
    static var tokenExpiresAt: Date? {
        get { credentials?.expiresAt }
        set {
            guard var current = credentials else { return }
            current.expiresAt = newValue
            credentials = current
        }
    }

    /// Persist a full token pair (access + refresh + expiry) atomically in Keychain.
    /// May be called by BOTH the host app and the widget — the widget
    /// rotates the pair itself when the app has not been running past the
    /// token's ~8h lifetime (see TokenManager for the race protocol).
    static func storeTokenPair(accessToken: String,
                               refreshToken: String?,
                               expiresInSeconds: Int,
                               now: Date = Date()) {
        let trimmedRefresh = refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        let creds = StoredCredentials(
            accessToken: accessToken,
            refreshToken: (trimmedRefresh?.isEmpty == false) ? trimmedRefresh : nil,
            expiresAt: now.addingTimeInterval(TimeInterval(expiresInSeconds))
        )
        credentials = creds
    }

    /// Clear all credentials (sign out / refresh token revoked).
    static func clearCredentials() {
        migrateIfNeeded()
        credentialStore.clear()
        scrubPlaintextCredentials(from: rawDefaults)
    }

    // MARK: - Cached Display & Settings (UserDefaults)

    static var cachedDisplay: QuotaDisplay? {
        get {
            guard let data = defaults.data(forKey: "cachedDisplay") else { return nil }
            return try? JSONDecoder().decode(QuotaDisplay.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "cachedDisplay")
            } else {
                defaults.removeObject(forKey: "cachedDisplay")
            }
        }
    }

    /// When the host app last refreshed (its timer ticks at the shared
    /// interval). The widget reads this to decide whether the app is alive:
    /// while it is, the app owns fetching AND token renewal; once it goes
    /// stale, the widget starts rotating the token pair itself.
    static var appHeartbeat: Date? {
        get { defaults.object(forKey: "appHeartbeat") as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: "appHeartbeat")
            } else {
                defaults.removeObject(forKey: "appHeartbeat")
            }
        }
    }

    /// Widget 刷新间隔（分钟）。在宿主 App 内设置，可选 5/10/30/60。
    static var refreshIntervalMinutes: Int {
        get {
            let value = defaults.integer(forKey: "refreshIntervalMinutes")
            return [5, 10, 30, 60].contains(value) ? value : 30
        }
        set {
            defaults.set(newValue, forKey: "refreshIntervalMinutes")
        }
    }

    /// Whether to show the app icon in the macOS Dock.
    /// Defaults to `false` (pure Menu Bar accessory mode).
    static var showDockIcon: Bool {
        get { defaults.bool(forKey: "showDockIcon") }
        set { defaults.set(newValue, forKey: "showDockIcon") }
    }
}
