import Foundation
import SwiftUI
import AppKit
import WidgetKit
import os

private let coordLog = Logger(subsystem: "app.solocraft.quotaring", category: "coordinator")

@MainActor
final class QuotaCoordinator: ObservableObject {
    @Published var accounts: [ProviderAccount] = []
    @Published var snapshots: [UUID: ProviderSnapshot] = [:]
    @Published var accountErrors: [UUID: String] = [:]
    @Published var isRefreshing = false

    @Published var refreshInterval = 30
    @Published var launchAtLogin = false
    @Published var showDockIcon = false

    @Published var availableUpdate: UpdateInfo?
    @Published var isCheckingUpdates = false
    @Published var updateStatusMessage: String?

    private let store: SharedSnapshotStore
    private let vault: CredentialVaulting
    private let registry: ProviderRegistry
    private let reloadWidgets: () -> Void
    private let autoStart: Bool

    private var refreshTimer: Timer?
    private var lastUpdateCheck: Date?
    private var observers: [NSObjectProtocol] = []

    init(
        store: SharedSnapshotStore = .shared,
        vault: CredentialVaulting = KeychainVault(),
        registry: ProviderRegistry = .default,
        autoStart: Bool = true,
        reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.store = store
        self.vault = vault
        self.registry = registry
        self.autoStart = autoStart
        self.reloadWidgets = reloadWidgets

        if autoStart {
            LegacyV1Migration.migrateIfNeeded(store: store, vault: vault)
        }
        loadFromStore()

        if autoStart {
            startAutoRefresh()
            installWorkspaceObservers()
            if !accounts.isEmpty {
                Task { await refreshAll(silent: !snapshots.isEmpty) }
            }
            Task { await checkForUpdatesIfDue() }
            reloadWidgets()
        }
    }

    func loadFromStore() {
        accounts = store.accounts
        var map: [UUID: ProviderSnapshot] = [:]
        for snap in store.snapshots {
            map[snap.accountID] = snap
        }
        snapshots = map
        syncPreferences()
    }

    func syncPreferences() {
        refreshInterval = store.refreshIntervalMinutes
        showDockIcon = store.showDockIcon
        if autoStart {
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    private func installWorkspaceObservers() {
        let wakeCenter = NSWorkspace.shared.notificationCenter
        observers.append(wakeCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshIfStale(reason: "wake")
                await self?.checkForUpdatesIfDue()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfStale(reason: "app-active") }
        })
    }

    // MARK: - Preferences

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = LaunchAtLogin.setEnabled(enabled)
    }

    func setShowDockIcon(_ show: Bool) {
        store.showDockIcon = show
        showDockIcon = show
        let policy: NSApplication.ActivationPolicy = show ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
        if show {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func saveRefreshInterval(_ minutes: Int) {
        store.refreshIntervalMinutes = minutes
        refreshInterval = minutes
        if autoStart {
            startAutoRefresh()
        }
        reloadWidgets()
        Task { await refreshAll(silent: true) }
    }

    func startAutoRefresh() {
        refreshTimer?.invalidate()
        let seconds = TimeInterval(store.refreshIntervalMinutes * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAll(silent: true)
            }
        }
    }

    // MARK: - Account Management

    /// Adds (or replaces in v2.0 single-per-kind UI) a GitHub Copilot account with OAuth credentials.
    @discardableResult
    func addCopilotAccount(pair: GitHubDeviceFlow.TokenPair) -> ProviderAccount {
        // Replace existing Copilot account if present in v2.0 single-account-per-provider UI.
        if let existing = accounts.first(where: { $0.kind == .copilot }) {
            let creds = StoredCredentials(
                accessToken: pair.accessToken,
                refreshToken: pair.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(pair.expiresInSeconds))
            )
            vault.save(.oauth(creds), for: existing.id)
            accountErrors[existing.id] = nil
            Task { await refresh(account: existing) }
            return existing
        }

        let account = ProviderAccount(
            kind: .copilot,
            sortOrder: (accounts.map(\.sortOrder).max() ?? -1) + 1
        )
        let creds = StoredCredentials(
            accessToken: pair.accessToken,
            refreshToken: pair.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(pair.expiresInSeconds))
        )
        vault.save(.oauth(creds), for: account.id)
        accounts.append(account)
        store.accounts = accounts
        reloadWidgets()
        Task { await refresh(account: account) }
        return account
    }

    /// Adds an API-key-based provider account (DeepSeek, OpenRouter, GLM).
    @discardableResult
    func addAPIKeyAccount(
        kind: ProviderKind,
        apiKey: String,
        displayName: String? = nil,
        region: String? = nil,
        balanceReferenceCap: Double? = nil,
        warningThreshold: Double? = nil,
        criticalThreshold: Double? = nil
    ) -> ProviderAccount {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = ProviderAccount(
            kind: kind,
            displayName: (trimmedName?.isEmpty == false) ? trimmedName : nil,
            region: region,
            balanceReferenceCap: balanceReferenceCap,
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold,
            sortOrder: (accounts.map(\.sortOrder).max() ?? -1) + 1
        )
        vault.save(.apiKey(trimmedKey), for: account.id)
        accounts.append(account)
        store.accounts = accounts
        reloadWidgets()
        Task { await refresh(account: account) }
        return account
    }

    func updateAccount(_ updated: ProviderAccount, newAPIKey: String? = nil) {
        guard let idx = accounts.firstIndex(where: { $0.id == updated.id }) else { return }
        accounts[idx] = updated
        store.accounts = accounts
        if let newAPIKey {
            let trimmed = newAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                vault.save(.apiKey(trimmed), for: updated.id)
            }
        }
        reloadWidgets()
        Task { await refresh(account: updated) }
    }

    func removeAccount(_ account: ProviderAccount) {
        vault.delete(accountID: account.id)
        accounts.removeAll { $0.id == account.id }
        snapshots.removeValue(forKey: account.id)
        accountErrors.removeValue(forKey: account.id)
        store.accounts = accounts
        store.removeSnapshot(for: account.id)
        reloadWidgets()
    }

    // MARK: - Refreshing

    func refreshIfStale(reason: String) async {
        let enabled = accounts.filter(\.isEnabled)
        guard !enabled.isEmpty else { return }
        let interval = TimeInterval(store.refreshIntervalMinutes * 60)
        let oldest = enabled.compactMap { snapshots[$0.id]?.fetchedAt }.min()
        if let oldest, Date().timeIntervalSince(oldest) < interval {
            return
        }
        coordLog.info("refresh (\(reason, privacy: .public)): cache stale")
        await refreshAll(silent: true)
    }

    func refresh(account: ProviderAccount) async {
        guard let provider = registry.provider(for: account.kind) else { return }
        store.appHeartbeat = Date()
        do {
            let snap = try await provider.fetchSnapshot(account: account, vault: vault)
            snapshots[account.id] = snap
            accountErrors[account.id] = nil
            store.upsertSnapshot(snap)
            reloadWidgets()
        } catch {
            accountErrors[account.id] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            coordLog.error("refresh failed for \(account.kind.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Concurrently refreshes all enabled accounts with per-account error isolation.
    func refreshAll(silent: Bool = false) async {
        let enabled = accounts.filter(\.isEnabled)
        guard !enabled.isEmpty else { return }
        guard !isRefreshing else { return }

        store.appHeartbeat = Date()
        isRefreshing = !silent
        defer { isRefreshing = false }

        let registry = self.registry
        let vault = self.vault

        let results: [(UUID, Result<ProviderSnapshot, Error>)] = await withTaskGroup(
            of: (UUID, Result<ProviderSnapshot, Error>).self
        ) { group in
            for account in enabled {
                guard let provider = registry.provider(for: account.kind) else { continue }
                group.addTask {
                    do {
                        let snap = try await provider.fetchSnapshot(account: account, vault: vault)
                        return (account.id, .success(snap))
                    } catch {
                        return (account.id, .failure(error))
                    }
                }
            }
            var collected: [(UUID, Result<ProviderSnapshot, Error>)] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }

        for (accountID, result) in results {
            switch result {
            case .success(let snap):
                snapshots[accountID] = snap
                accountErrors[accountID] = nil
                store.upsertSnapshot(snap)
            case .failure(let error):
                accountErrors[accountID] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        reloadWidgets()
    }

    // MARK: - Updates

    func checkForUpdatesIfDue() async {
        if let last = lastUpdateCheck, Date().timeIntervalSince(last) < 24 * 3600 {
            return
        }
        await checkForUpdates(userInitiated: false)
    }

    func checkForUpdates(userInitiated: Bool) async {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        if userInitiated { updateStatusMessage = nil }
        defer { isCheckingUpdates = false }

        lastUpdateCheck = Date()
        let result = await UpdateChecker().check()
        switch result {
        case .available(let info):
            availableUpdate = info
            updateStatusMessage = nil
        case .upToDate:
            availableUpdate = nil
            if userInitiated {
                updateStatusMessage = L("You’re up to date (v%@).", AppInfo.version)
            }
        case .failed(let message):
            if userInitiated {
                updateStatusMessage = message
            }
        }
    }
}
