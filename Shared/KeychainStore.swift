import Foundation
import Security
import os

private let keychainLog = Logger(subsystem: "app.solocraft.copilotquota", category: "keychain")

/// Atomic credential payload persisted in Keychain.
///
/// Storing access token, rotating refresh token, and expiry together in a
/// single Keychain item ensures updates from either the host app or widget
/// are atomic.
struct StoredCredentials: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
}

/// Persistence interface for OAuth credentials (Keychain in production,
/// in-memory in unit tests).
protocol CredentialStoring {
    func load() -> StoredCredentials?
    @discardableResult
    func save(_ credentials: StoredCredentials) -> Bool
    func clear()
}

/// macOS Keychain-backed credential store shared between the host app and
/// its embedded WidgetKit extension.
final class KeychainCredentialStore: CredentialStoring {
    let service: String
    let account: String

    init(service: String = "app.solocraft.copilotquota", account: String = "github-oauth") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() -> StoredCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                keychainLog.error("Keychain read failed (OSStatus \(status, privacy: .public))")
            }
            return nil
        }
        return try? JSONDecoder().decode(StoredCredentials.self, from: data)
    }

    @discardableResult
    func save(_ credentials: StoredCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }

        // Prefer SecItemUpdate when the item already exists: on macOS this
        // preserves the existing SecAccess ACL (which trusts both host app and
        // widget extension) across token rotations.
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            keychainLog.error("Keychain update failed (OSStatus \(updateStatus, privacy: .public)) — recreating item")
            SecItemDelete(baseQuery as CFDictionary)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrLabel as String] = "Copilot Quota (GitHub OAuth)"
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        if let access = makeSharedAccess() {
            addQuery[kSecAttrAccess as String] = access
        }

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            keychainLog.error("Keychain add failed (OSStatus \(addStatus, privacy: .public))")
            return false
        }
        return true
    }

    func clear() {
        let status = SecItemDelete(baseQuery as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            keychainLog.error("Keychain delete failed (OSStatus \(status, privacy: .public))")
        }
    }

    /// Build a Keychain ACL trusting both the current host app and its embedded
    /// widget extension, so the widget can read and rotate tokens without
    /// triggering macOS Keychain prompts.
    private func makeSharedAccess() -> SecAccess? {
        var trustedApps: [SecTrustedApplication] = []

        var selfApp: SecTrustedApplication?
        if SecTrustedApplicationCreateFromPath(nil, &selfApp) == errSecSuccess, let selfApp {
            trustedApps.append(selfApp)
        }

        if let widgetPath = embeddedWidgetPath() {
            var widgetApp: SecTrustedApplication?
            if SecTrustedApplicationCreateFromPath(widgetPath, &widgetApp) == errSecSuccess, let widgetApp {
                trustedApps.append(widgetApp)
            }
        }

        guard !trustedApps.isEmpty else { return nil }
        var access: SecAccess?
        let status = SecAccessCreate(
            "Copilot Quota" as CFString,
            trustedApps as CFArray,
            &access
        )
        return status == errSecSuccess ? access : nil
    }

    private func embeddedWidgetPath() -> String? {
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasSuffix(".app") else { return nil }
        let widgetPath = (bundlePath as NSString)
            .appendingPathComponent("Contents/PlugIns/CopilotQuotaWidget.appex")
        return FileManager.default.fileExists(atPath: widgetPath) ? widgetPath : nil
    }
}

/// Thread-safe in-memory credential store for unit tests.
final class InMemoryCredentialStore: CredentialStoring {
    private let lock = NSLock()
    private var stored: StoredCredentials?

    init(initial: StoredCredentials? = nil) {
        self.stored = initial
    }

    func load() -> StoredCredentials? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    @discardableResult
    func save(_ credentials: StoredCredentials) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        stored = credentials
        return true
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        stored = nil
    }
}
