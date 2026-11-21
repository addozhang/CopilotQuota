import Foundation

/// Shared non-sensitive state between the QuotaRing host app and its pure-renderer Widget extension.
///
/// No secrets are ever stored here — only configured account metadata,
/// sanitized quota snapshots, refresh interval, and UI preferences.
public final class SharedSnapshotStore: @unchecked Sendable {
    public static let suiteName = "app.solocraft.quotaring"
    public static let shared = SharedSnapshotStore()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: Self.suiteName) ?? .standard
    }

    public var accounts: [ProviderAccount] {
        get {
            guard let data = defaults.data(forKey: "accounts"),
                  let decoded = try? JSONDecoder().decode([ProviderAccount].self, from: data) else {
                return []
            }
            return decoded.sorted { $0.sortOrder < $1.sortOrder }
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "accounts")
            }
        }
    }

    public var snapshots: [ProviderSnapshot] {
        get {
            guard let data = defaults.data(forKey: "snapshots"),
                  let decoded = try? JSONDecoder().decode([ProviderSnapshot].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "snapshots")
            }
        }
    }

    public func snapshot(for accountID: UUID) -> ProviderSnapshot? {
        snapshots.first(where: { $0.accountID == accountID })
    }

    public func upsertSnapshot(_ snapshot: ProviderSnapshot) {
        var current = snapshots
        if let idx = current.firstIndex(where: { $0.accountID == snapshot.accountID }) {
            current[idx] = snapshot
        } else {
            current.append(snapshot)
        }
        snapshots = current
    }

    public func removeSnapshot(for accountID: UUID) {
        snapshots = snapshots.filter { $0.accountID != accountID }
    }

    public var refreshIntervalMinutes: Int {
        get {
            let value = defaults.integer(forKey: "refreshIntervalMinutes")
            return [5, 10, 30, 60].contains(value) ? value : 30
        }
        set {
            defaults.set(newValue, forKey: "refreshIntervalMinutes")
        }
    }

    /// Defaults to `false` (pure Menu Bar accessory mode).
    public var showDockIcon: Bool {
        get { defaults.bool(forKey: "showDockIcon") }
        set { defaults.set(newValue, forKey: "showDockIcon") }
    }

    public var appHeartbeat: Date? {
        get { defaults.object(forKey: "appHeartbeat") as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: "appHeartbeat")
            } else {
                defaults.removeObject(forKey: "appHeartbeat")
            }
        }
    }

    public var v1MigrationCompleted: Bool {
        get { defaults.bool(forKey: "v1MigrationCompleted") }
        set { defaults.set(newValue, forKey: "v1MigrationCompleted") }
    }
}
