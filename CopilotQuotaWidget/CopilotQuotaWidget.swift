import WidgetKit
import SwiftUI
import os

private let widgetLog = Logger(subsystem: "app.solocraft.copilotquota", category: "widget")

struct QuotaEntry: TimelineEntry {
    let date: Date
    let display: QuotaDisplay?
    let needsSetup: Bool
}

struct QuotaProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: .now, display: .placeholder, needsSetup: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(currentEntry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let now = Date.now
        // 刷新间隔在宿主 App 内设置（5/10/30/60 分钟，默认 30）。
        let refreshInterval = TimeInterval(SharedStore.refreshIntervalMinutes * 60)
        guard SharedStore.token != nil else {
            finish(nil, needsSetup: true, at: now, policy: min(refreshInterval, 1800), completion)
            return
        }
        // While the host app is alive its timer owns fetching AND token
        // renewal (networking from the app is not budget-limited, and every
        // successful fetch is pushed via reloadAllTimelines). Just render
        // the cache it keeps fresh.
        if appIsAlive(now, refreshInterval: refreshInterval) {
            widgetLog.info("reload: app alive — rendering app cache")
            finish(SharedStore.cachedDisplay, needsSetup: false, at: now, policy: refreshInterval, completion)
            return
        }
        // When the host app just refreshed and called reloadAllTimelines(),
        // cachedDisplay is already fresh — render it immediately without a
        // duplicate network round-trip. (Covers the app-just-quit edge too.)
        if let cached = SharedStore.cachedDisplay,
           now.timeIntervalSince(cached.fetchedAt) < 60 {
            widgetLog.info("reload: cache <60s — skipping fetch")
            finish(cached, needsSetup: false, at: now, policy: refreshInterval, completion)
            return
        }
        // App not running: fetch for ourselves. validToken rotates the ~8h
        // access token when needed (persisting the new pair via the shared
        // domain) — this is what keeps the widget updating days after the
        // app last ran instead of silently serving a stale snapshot.
        widgetLog.info("reload: app quiet — self-serving fetch")
        Task {
            var display = SharedStore.cachedDisplay
            do {
                let token = try await TokenManager.validToken(mayClearCredentials: false)
                let response = try await CopilotQuotaClient().fetch(token: token)
                if let fresh = response.display {
                    display = fresh
                    SharedStore.cachedDisplay = fresh
                    widgetLog.info("self-fetch ok: \(fresh.primaryCategoryLabel, privacy: .public) \(fresh.percentRemaining, format: .fixed(precision: 0), privacy: .public)%")
                }
            } catch {
                // Rotation or fetch failed (e.g. refresh token dead): keep
                // showing the last cached value; the app sorts out sign-in.
                widgetLog.error("self-fetch failed: \(error.localizedDescription, privacy: .public)")
            }
            finish(display, needsSetup: false, at: now, policy: refreshInterval, completion)
        }
    }

    /// The host app's timer heartbeats on every refresh. Give it a generous
    /// window (2 ticks + 10 min) before deciding it is not running and the
    /// widget must rotate the token pair on its own.
    private func appIsAlive(_ now: Date, refreshInterval: TimeInterval) -> Bool {
        guard let heartbeat = SharedStore.appHeartbeat else { return false }
        return now.timeIntervalSince(heartbeat) < refreshInterval * 2 + 600
    }

    private func finish(_ display: QuotaDisplay?, needsSetup: Bool, at now: Date,
                        policy: TimeInterval,
                        _ completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        completion(Timeline(entries: [QuotaEntry(date: now, display: display, needsSetup: needsSetup)],
                            policy: .after(now.addingTimeInterval(policy))))
    }

    private var currentEntry: QuotaEntry {
        QuotaEntry(date: .now,
                   display: SharedStore.cachedDisplay,
                   needsSetup: SharedStore.token == nil)
    }
}

struct CopilotQuotaEntryView: View {
    let entry: QuotaEntry

    var body: some View {
        smallWidget
            .containerBackground(for: .widget) {
                Rectangle().fill(.thinMaterial)
            }
    }

    /// systemSmall: ring + percentage, styled after the system battery widget —
    /// the ring/label group is centered with generous spacing between them.
    private var smallWidget: some View {
        VStack(spacing: 20) {
            QuotaRingView(percent: entry.display?.percentRemaining, size: 64)
            Text(percentText)
                .font(.system(size: 20, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // centers the group
        // 点击小组件打开 App（登录与刷新间隔设置都在 App 内）。
        .widgetURL(URL(string: "copilotquota://open"))
    }

    private var percentText: String {
        guard let display = entry.display else { return "—" }
        return "\(Int(display.percentRemaining.rounded()))%"
    }
}

struct CopilotQuotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.solocraft.copilotquota.quota", provider: QuotaProvider()) { entry in
            CopilotQuotaEntryView(entry: entry)
        }
        .configurationDisplayName("Copilot Quota")
        .description("Shows your remaining GitHub Copilot quota.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct CopilotQuotaWidgetBundle: WidgetBundle {
    var body: some Widget {
        CopilotQuotaWidget()
    }
}
