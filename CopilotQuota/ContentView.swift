import SwiftUI
import AppKit
import WidgetKit

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        Group {
            if model.token == nil {
                DeviceFlowView(model: model)
            } else {
                StatusView(model: model)
            }
        }
        .frame(width: 420, height: 480)
        .onAppear { model.load() }
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

    private var refreshTimer: Timer?

    func load() {
        token = SharedStore.token
        display = SharedStore.cachedDisplay
        refreshInterval = SharedStore.refreshIntervalMinutes
        startAutoRefresh()
        // Push a fresh timeline after app updates — otherwise the system may
        // keep rendering the stale widget snapshot (old layout/data) until the
        // next scheduled reload lands.
        WidgetCenter.shared.reloadAllTimelines()
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
            WidgetCenter.shared.reloadAllTimelines()
        } catch QuotaError.unauthorized where SharedStore.token == nil {
            // Refresh token died — TokenManager already cleared credentials.
            token = nil
        } catch {
            errorText = (error as? QuotaError)?.errorDescription ?? error.localizedDescription
        }
    }

    func signOut() {
        SharedStore.clearCredentials()
        SharedStore.cachedDisplay = nil
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

    var body: some View {
        VStack(spacing: 16) {
            header

            if let display = model.display {
                HStack(spacing: 12) {
                    if let premium = display.premium {
                        CategoryCard(label: "Premium", quota: premium)
                    }
                    if let chat = display.chat {
                        CategoryCard(label: "Chat", quota: chat)
                    }
                    if let completions = display.completions {
                        CategoryCard(label: "Completions", quota: completions)
                    }
                }

                HStack(spacing: 14) {
                    if let reset = display.resetDate {
                        Label(L("Quota resets on %@", display.resetDateLocalized ?? reset),
                              systemImage: "calendar.badge.clock")
                    }
                    HStack(spacing: 4) {
                        Text(L("Updated at %@", display.fetchedAt.formatted(date: .omitted, time: .shortened)))
                        Text("·")
                        // Live-updating relative time makes staleness obvious.
                        Text(display.fetchedAt, style: .relative)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if model.isRefreshing {
                Spacer()
                ProgressView(L("Fetching quota…"))
                Spacer()
            }

            // 刷新间隔设置（写入共享存储，widget 立即按新间隔重排）
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("Widget refresh interval"))
                        .font(.callout)
                    Spacer()
                    Picker(L("Widget refresh interval"), selection: Binding(
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
                    .frame(width: 130)
                }
                Text(L("The system applies a daily widget reload budget; actual frequency may be throttled."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let error = model.errorText {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Divider()
            HStack {
                Text(L("Add to desktop: right-click the desktop → Edit Widgets → search “Copilot”"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Link(destination: AppInfo.repoURL) {
                    Label("GitHub", systemImage: "star")
                }
                .font(.caption)
                .linkCursor()
                Button(L("Sign Out")) { model.signOut() }
                    .buttonStyle(.link)
                    .foregroundStyle(.red)
                    .linkCursor()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.06))
                CopilotIconShape().fill(.primary).frame(width: 30, height: 30)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.display?.login ?? "GitHub Copilot")
                    .font(.headline)
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

struct CategoryCard: View {
    let label: String
    let quota: CategoryQuota

    private var percentText: String {
        quota.percentRemaining.map { "\(Int($0.rounded()))%" } ?? "∞"
    }

    var body: some View {
        VStack(spacing: 8) {
            QuotaRingView(percent: quota.unlimited ? 100 : quota.percentRemaining,
                          size: 46)
            Text(percentText)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}
