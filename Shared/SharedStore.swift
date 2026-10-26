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
