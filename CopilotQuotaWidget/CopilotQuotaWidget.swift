import WidgetKit
import SwiftUI

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
        guard let token = SharedStore.token else {
            completion(Timeline(entries: [QuotaEntry(date: now, display: nil, needsSetup: true)],
                                policy: .after(now.addingTimeInterval(min(refreshInterval, 1800)))))
            return
        }
        // When the host app just refreshed and called reloadAllTimelines(),
        // cachedDisplay is already fresh — render it immediately without a
        // duplicate network round-trip.
        if let cached = SharedStore.cachedDisplay,
           now.timeIntervalSince(cached.fetchedAt) < 60 {
            completion(Timeline(entries: [QuotaEntry(date: now, display: cached, needsSetup: false)],
                                policy: .after(now.addingTimeInterval(refreshInterval))))
            return
        }
        Task {
            var display = SharedStore.cachedDisplay
            do {
                let response = try await CopilotQuotaClient().fetch(token: token)
                if let fresh = response.display {
                    display = fresh
                    SharedStore.cachedDisplay = fresh
                }
            } catch {
                // Keep showing the last cached value.
            }
            completion(Timeline(entries: [QuotaEntry(date: now, display: display, needsSetup: false)],
                                policy: .after(now.addingTimeInterval(refreshInterval))))
        }
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
        StaticConfiguration(kind: "com.addo.copilotquota.quota", provider: QuotaProvider()) { entry in
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
