import Foundation

/// Values shared between the host app and the widget extension.
///
/// The host app is unsandboxed and writes the plain preference domain
/// `com.addo.copilotquota`; the sandboxed widget extension reads that same
/// domain via a `temporary-exception.shared-preference.read-only` grant
/// (see CopilotQuotaWidget.entitlements).
enum SharedStore {
    static let suiteName = "com.addo.copilotquota"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static var token: String? {
        get {
            let raw = defaults.string(forKey: "githubToken")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty == false) ? raw : nil
        }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: "githubToken")
            } else {
                defaults.removeObject(forKey: "githubToken")
            }
        }
    }

    /// OAuth refresh token (`ghr_…`). GitHub rotates it on every refresh —
    /// each refresh response returns a NEW refresh token and invalidates the
    /// old one, so both values must be persisted together, atomically.
    /// Only the host app may write it; the widget has read-only access.
    static var refreshToken: String? {
        get {
            let raw = defaults.string(forKey: "githubRefreshToken")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty == false) ? raw : nil
        }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: "githubRefreshToken")
            } else {
                defaults.removeObject(forKey: "githubRefreshToken")
            }
        }
    }

    /// When the current access token expires (nil = unknown, legacy login).
    static var tokenExpiresAt: Date? {
        get { defaults.object(forKey: "githubTokenExpiresAt") as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: "githubTokenExpiresAt")
            } else {
                defaults.removeObject(forKey: "githubTokenExpiresAt")
            }
        }
    }

    /// Persist a full token pair (access + refresh + expiry) in one go.
    /// (Plain values, not a GitHubDeviceFlow.TokenPair, because the widget
    /// target compiles this file but not GitHubDeviceFlow.swift.)
    static func storeTokenPair(accessToken: String, refreshToken: String?, expiresInSeconds: Int) {
        token = accessToken
        self.refreshToken = refreshToken
        tokenExpiresAt = Date().addingTimeInterval(TimeInterval(expiresInSeconds))
    }

    /// Clear all credentials (sign out / refresh token revoked).
    static func clearCredentials() {
        token = nil
        refreshToken = nil
        tokenExpiresAt = nil
    }

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
}
