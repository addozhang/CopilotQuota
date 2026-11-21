import SwiftUI
import AppKit
import WidgetKit
import os

private let logger = Logger(subsystem: "app.solocraft.copilotquota", category: "app")

enum ContentPresentation {
    case popover
    case window
}

struct ContentView: View {
    var presentation: ContentPresentation = .window

    // Owned by the App scene so the auto-refresh timer survives closing
    // the window (and keeps running in Menu Bar mode).
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if model.token == nil {
                DeviceFlowView(model: model, isPopover: presentation == .popover)
            } else {
                StatusView(model: model, presentation: presentation)
            }
        }
        .frame(width: presentation == .popover ? 332 : 380)
        .onAppear { model.syncPreferences() }
    }
}

// MARK: - Model

@MainActor
final class AppModel: ObservableObject {
    @Published var token: String?
    @Published var display: QuotaDisplay?
    @Published var isRefreshing = false
    @Published var errorText: String?
    @Published var refreshInterval = 30
    @Published var launchAtLogin = false
    @Published var showDockIcon = false

    @Published var availableUpdate: UpdateInfo?
    @Published var isCheckingUpdates = false
    @Published var updateStatusMessage: String?

    private var refreshTimer: Timer?
    private var lastUpdateCheck: Date?
    // Block-based observers; AppModel lives for the app's whole lifetime,
    // so they are never unregistered (process teardown cleans up).
    private var observers: [NSObjectProtocol] = []

    var menuBarPercentText: String? {
        guard token != nil, let display else { return nil }
        if display.isPrimaryUnlimited { return "∞" }
        return "\(Int(display.percentRemaining.rounded()))%"
    }

    init() {
        // Start refreshing at app launch (not first window open) — keeping the
        // app running in the Menu Bar keeps quota and OAuth tokens fresh.
        load()

        // Timers don't fire while the Mac sleeps, and App Nap can coalesce
        // them when occluded. Catch up when the system wakes or app activates.
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

        Task { await checkForUpdatesIfDue() }
    }

    func load() {
        token = SharedStore.token
        display = SharedStore.cachedDisplay
        syncPreferences()
        startAutoRefresh()
        if token != nil {
            Task { await refresh(silent: display != nil) }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func syncPreferences() {
        refreshInterval = SharedStore.refreshIntervalMinutes
        showDockIcon = SharedStore.showDockIcon
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = LaunchAtLogin.setEnabled(enabled)
    }

    func setShowDockIcon(_ show: Bool) {
        SharedStore.showDockIcon = show
        showDockIcon = show
        let policy: NSApplication.ActivationPolicy = show ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
        if show {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// The interval timer can miss beats (sleep, App Nap). When the system
    /// wakes or the app comes back to the front, refresh right away if the
    /// cache is older than one interval.
    func refreshIfStale(reason: String) async {
        guard token != nil else { return }
        let interval = TimeInterval(SharedStore.refreshIntervalMinutes * 60)
        if let fetchedAt = display?.fetchedAt, Date().timeIntervalSince(fetchedAt) < interval {
            return
        }
        logger.info("refresh (\(reason, privacy: .public)): cache older than interval")
        await refresh(silent: true)
    }

    /// While the app is open, poll at the chosen interval — networking from the
    /// app is NOT subject to the widget refresh budget — and reload the widget
    /// timelines after every successful fetch.
    func startAutoRefresh() {
        refreshTimer?.invalidate()
        let seconds = TimeInterval(SharedStore.refreshIntervalMinutes * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh(silent: true)
            }
        }
    }

    /// 保存刷新间隔并立即让小组件按新间隔重排 timeline。
    func saveRefreshInterval(_ minutes: Int) {
        SharedStore.refreshIntervalMinutes = minutes
        startAutoRefresh()
        WidgetCenter.shared.reloadAllTimelines()
        Task { await self.refresh(silent: true) }
    }

    func refresh(silent: Bool = false) async {
        guard token != nil else { return }
        guard !isRefreshing else { return }
        SharedStore.appHeartbeat = Date()
        isRefreshing = !silent
        errorText = nil
        defer { isRefreshing = false }
        do {
            let response = try await TokenManager.fetchQuota()
            guard let display = response.display else {
                throw QuotaError.notFound
            }
            self.display = display
            SharedStore.cachedDisplay = display
            logger.info("refresh ok: \(display.primaryCategoryLabel, privacy: .public) \(display.percentRemaining, format: .fixed(precision: 0), privacy: .public)%")
            WidgetCenter.shared.reloadAllTimelines()
        } catch QuotaError.unauthorized where SharedStore.token == nil {
            logger.error("signed out: refresh token rejected")
            token = nil
        } catch {
            errorText = (error as? QuotaError)?.errorDescription ?? error.localizedDescription
            logger.error("refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func checkForUpdatesIfDue() async {
        if let last = lastUpdateCheck, Date().timeIntervalSince(last) < 24 * 3600 {
            return
        }
        await checkForUpdates(userInitiated: false)
    }

    func checkForUpdates(userInitiated: Bool) async {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        if userInitiated {
            updateStatusMessage = nil
        }
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

    func signOut() {
        SharedStore.clearCredentials()
        SharedStore.cachedDisplay = nil
        SharedStore.appHeartbeat = nil
        token = nil
        display = nil
        errorText = nil
        refreshTimer?.invalidate()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Signed-in status

struct StatusView: View {
    @ObservedObject var model: AppModel
    var presentation: ContentPresentation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 14) {
            header

            if let display = model.display {
                primaryQuotaCard(display)
            } else if model.isRefreshing {
                ProgressView(L("Fetching quota…"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            }

            if let update = model.availableUpdate {
                updateBanner(update)
            } else if let status = model.updateStatusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = model.errorText {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            settingsSection

            Divider()

            footer
        }
        .padding(presentation == .popover ? 16 : 22)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.06))
                CopilotIconShape().fill(.primary).frame(width: 24, height: 24)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.display?.login ?? "GitHub Copilot")
                    .font(.headline)
                    .lineLimit(1)
                if let plan = model.display?.planLabel {
                    Text(plan)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task { await model.refresh() }
            } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(model.isRefreshing)
            .help(L("Refresh quota"))
            .linkCursor()
        }
    }

    private func primaryQuotaCard(_ display: QuotaDisplay) -> some View {
        HStack(spacing: 16) {
            QuotaRingView(
                percent: display.isPrimaryUnlimited ? 100 : display.percentRemaining,
                size: 68
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(display.isPrimaryUnlimited
                         ? "∞"
                         : "\(Int(display.percentRemaining.rounded()))%")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()

                    if let countText = display.primaryCountText {
                        Text(countText)
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                if let resetText = resetSummary(display) {
                    Label(resetText, systemImage: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text(L("Updated at %@", display.fetchedAt.formatted(date: .omitted, time: .shortened)))
                    Text("·")
                    Text(display.fetchedAt, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func resetSummary(_ display: QuotaDisplay) -> String? {
        guard let reset = display.resetDate else { return nil }
        let dateStr = display.resetDateLocalized ?? reset
        if let days = display.daysUntilReset() {
            return L("Resets %@ (%d d left)", dateStr, days)
        }
        return L("Quota resets on %@", dateStr)
    }

    private func updateBanner(_ update: UpdateInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text(L("Update available: v%@", update.version))
                .font(.caption.weight(.medium))
            Spacer()
            Button(L("Download")) {
                NSWorkspace.shared.open(update.downloadURL)
            }
            .controlSize(.small)
            .linkCursor()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Refresh interval"))
                    .font(.callout)
                Spacer()
                Picker(L("Refresh interval"), selection: Binding(
                    get: { model.refreshInterval },
                    set: { newValue in
                        model.refreshInterval = newValue
                        model.saveRefreshInterval(newValue)
                    })) {
                    Text(L("%d min", 5)).tag(5)
                    Text(L("%d min", 10)).tag(10)
                    Text(L("%d min", 30)).tag(30)
                    Text(L("%d min", 60)).tag(60)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 112)
            }

            Toggle(L("Launch at login"), isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            .font(.callout)
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(L("Show Dock icon"), isOn: Binding(
                get: { model.showDockIcon },
                set: { model.setShowDockIcon($0) }
            ))
            .font(.callout)
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.checkForUpdates(userInitiated: true) }
            } label: {
                if model.isCheckingUpdates {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(L("Check for Updates"))
                }
            }
            .buttonStyle(.link)
            .font(.caption)
            .disabled(model.isCheckingUpdates)
            .linkCursor()

            if presentation == .popover {
                Button(L("About")) {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "about")
                }
                .buttonStyle(.link)
                .font(.caption)
                .linkCursor()
            } else {
                Link(destination: AppInfo.repoURL) {
                    Label("GitHub", systemImage: "star")
                }
                .font(.caption)
                .linkCursor()
            }

            Spacer()

            Button(L("Sign Out")) { model.signOut() }
                .buttonStyle(.link)
                .font(.caption)
                .foregroundStyle(.red)
                .linkCursor()

            if presentation == .popover {
                Button(L("Quit")) { NSApp.terminate(nil) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .linkCursor()
            }
        }
    }
}

// MARK: - Cursor

extension View {
    /// Pointing-hand cursor on hover — SwiftUI `Link` doesn't do this on macOS by default.
    func linkCursor() -> some View {
        onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
