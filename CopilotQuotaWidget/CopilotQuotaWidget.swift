import WidgetKit
import SwiftUI
import AppIntents
import os

private let widgetLog = Logger(subsystem: "app.solocraft.quotaring", category: "widget")

// MARK: - AppIntent Entities & Configurations

struct ProviderAccountEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Provider"
    static var defaultQuery = ProviderAccountQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct ProviderAccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ProviderAccountEntity] {
        let accounts = SharedSnapshotStore.shared.accounts
        return accounts
            .filter { identifiers.contains($0.id.uuidString) }
            .map { ProviderAccountEntity(id: $0.id.uuidString, title: $0.resolvedTitle) }
    }

    func suggestedEntities() async throws -> [ProviderAccountEntity] {
        SharedSnapshotStore.shared.accounts.map {
            ProviderAccountEntity(id: $0.id.uuidString, title: $0.resolvedTitle)
        }
    }

    func defaultResult() async -> ProviderAccountEntity? {
        guard let first = SharedSnapshotStore.shared.accounts.first else { return nil }
        return ProviderAccountEntity(id: first.id.uuidString, title: first.resolvedTitle)
    }
}

/// Dedicated entity/query for the Dual-Ring widget so its default selection
/// prefers multi-window providers (e.g. GLM 5h + 7d) instead of Copilot.
struct DualProviderAccountEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Provider"
    static var defaultQuery = DualProviderAccountQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct DualProviderAccountQuery: EntityQuery {
    private static func orderedAccounts() -> [ProviderAccount] {
        let store = SharedSnapshotStore.shared
        let snapshots = Dictionary(uniqueKeysWithValues: store.snapshots.map { ($0.accountID, $0) })
        let accounts = store.accounts.filter(\.isEnabled)
        let multiWindow = accounts.filter { acc in
            if case .rollingWindows(let windows) = snapshots[acc.id]?.metric {
                return windows.count >= 2
            }
            return acc.kind.isMultiWindow
        }
        let others = accounts.filter { acc in !multiWindow.contains(where: { $0.id == acc.id }) }
        return multiWindow + others
    }

    func entities(for identifiers: [String]) async throws -> [DualProviderAccountEntity] {
        Self.orderedAccounts()
            .filter { identifiers.contains($0.id.uuidString) }
            .map { DualProviderAccountEntity(id: $0.id.uuidString, title: $0.resolvedTitle) }
    }

    func suggestedEntities() async throws -> [DualProviderAccountEntity] {
        Self.orderedAccounts().map {
            DualProviderAccountEntity(id: $0.id.uuidString, title: $0.resolvedTitle)
        }
    }

    func defaultResult() async -> DualProviderAccountEntity? {
        guard let first = Self.orderedAccounts().first else { return nil }
        return DualProviderAccountEntity(id: first.id.uuidString, title: first.resolvedTitle)
    }
}

struct SelectSingleProviderIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Single Ring"
    static var description = IntentDescription("Choose which AI quota provider to display.")

    @Parameter(title: "Provider")
    var account: ProviderAccountEntity?
}

struct SelectDualProviderIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Dual Rings"
    static var description = IntentDescription("Choose a multi-window provider (GLM, Kimi Code, MiniMax) to display both rings.")

    @Parameter(title: "Provider")
    var account: DualProviderAccountEntity?
}

// MARK: - Timeline Entries & Providers (Pure Renderers)

struct SingleRingEntry: TimelineEntry {
    let date: Date
    let slot: WidgetRingSlot?
}

struct DualRingEntry: TimelineEntry {
    let date: Date
    let slots: [WidgetRingSlot]
}

struct SingleRingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SingleRingEntry {
        SingleRingEntry(
            date: .now,
            slot: WidgetRingSlot(id: "placeholder", kind: .copilot, title: "Copilot", presentation: .placeholder)
        )
    }

    func snapshot(for configuration: SelectSingleProviderIntent, in context: Context) async -> SingleRingEntry {
        makeEntry(for: configuration, at: .now)
    }

    func timeline(for configuration: SelectSingleProviderIntent, in context: Context) async -> Timeline<SingleRingEntry> {
        let now = Date.now
        let entry = makeEntry(for: configuration, at: now)
        let interval = TimeInterval(SharedSnapshotStore.shared.refreshIntervalMinutes * 60)
        return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(interval)))
    }

    private func makeEntry(for configuration: SelectSingleProviderIntent, at date: Date) -> SingleRingEntry {
        let store = SharedSnapshotStore.shared
        let snapshotsMap = Dictionary(uniqueKeysWithValues: store.snapshots.map { ($0.accountID, $0) })
        let selectedID = configuration.account.flatMap { UUID(uuidString: $0.id) }
        let slot = WidgetSlotResolver.resolveSingle(
            selectedAccountID: selectedID,
            accounts: store.accounts,
            snapshots: snapshotsMap
        )
        widgetLog.info("single timeline: accounts=\(store.accounts.count) selected=\(selectedID?.uuidString ?? "nil", privacy: .public) rendered=\(slot?.title ?? "empty", privacy: .public) \(slot?.presentation.primaryText ?? "—", privacy: .public)")
        return SingleRingEntry(date: date, slot: slot)
    }
}

struct DualRingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DualRingEntry {
        DualRingEntry(
            date: .now,
            slots: [
                WidgetRingSlot(
                    id: "p1",
                    kind: .glm,
                    title: "GLM Coding",
                    windowLabel: "5h",
                    presentation: RingPresentation(fillFraction: 1.0, tone: .normal, primaryText: "100%", secondaryText: nil)
                ),
                WidgetRingSlot(
                    id: "p2",
                    kind: .glm,
                    title: "GLM Coding",
                    windowLabel: "7d",
                    presentation: RingPresentation(fillFraction: 0.99, tone: .normal, primaryText: "99%", secondaryText: nil)
                ),
            ]
        )
    }

    func snapshot(for configuration: SelectDualProviderIntent, in context: Context) async -> DualRingEntry {
        makeEntry(for: configuration, at: .now)
    }

    func timeline(for configuration: SelectDualProviderIntent, in context: Context) async -> Timeline<DualRingEntry> {
        let now = Date.now
        let entry = makeEntry(for: configuration, at: now)
        let interval = TimeInterval(SharedSnapshotStore.shared.refreshIntervalMinutes * 60)
        return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(interval)))
    }

    private func makeEntry(for configuration: SelectDualProviderIntent, at date: Date) -> DualRingEntry {
        let store = SharedSnapshotStore.shared
        let snapshotsMap = Dictionary(uniqueKeysWithValues: store.snapshots.map { ($0.accountID, $0) })
        let selectedID = configuration.account.flatMap { UUID(uuidString: $0.id) }
        let slots = WidgetSlotResolver.resolveDual(
            selectedAccountID: selectedID,
            accounts: store.accounts,
            snapshots: snapshotsMap
        )
        let desc = slots.map { "\($0.title)=\($0.presentation.primaryText)" }.joined(separator: ", ")
        widgetLog.info("dual timeline: accounts=\(store.accounts.count) selected=\(selectedID?.uuidString ?? "nil", privacy: .public) rendered=[\(desc, privacy: .public)]")
        return DualRingEntry(date: date, slots: slots)
    }
}

// MARK: - Views

struct SingleRingEntryView: View {
    let entry: SingleRingEntry

    var body: some View {
        let presentation = entry.slot?.presentation ?? .empty
        let kind = entry.slot?.kind ?? .copilot

        VStack(spacing: 20) {
            QuotaRingView(presentation: presentation, kind: kind, size: 64)
            Text(presentation.primaryText)
                .font(.system(size: 20, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "quotaring://open"))
        .containerBackground(for: .widget) {
            Rectangle().fill(.thinMaterial)
        }
    }
}

struct DualRingEntryView: View {
    let entry: DualRingEntry

    var body: some View {
        Group {
            if let first = entry.slots.first {
                VStack(spacing: 12) {
                    // Single-provider identity header: brand glyph + provider name once at top.
                    HStack(spacing: 6) {
                        ProviderGlyphView(kind: first.kind, size: 14)
                        Text(first.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }

                    // Dual rings side-by-side: window badge (5h / 7d) inside each ring, clean % below.
                    HStack(spacing: 0) {
                        ForEach(entry.slots, id: \.id) { slot in
                            VStack(spacing: 10) {
                                QuotaRingView(
                                    presentation: slot.presentation,
                                    kind: slot.kind,
                                    centerLabel: slot.windowLabel,
                                    size: 62
                                )
                                Text(slot.presentation.primaryText)
                                    .font(.system(size: 19, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    QuotaRingView(presentation: .empty, kind: .glm, size: 54)
                    Text(L("Open QuotaRing to add providers"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .widgetURL(URL(string: "quotaring://open"))
        .containerBackground(for: .widget) {
            Rectangle().fill(.thinMaterial)
        }
    }
}

// MARK: - Widgets & Bundle

struct SingleRingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "app.solocraft.quotaring.single",
            intent: SelectSingleProviderIntent.self,
            provider: SingleRingProvider()
        ) { entry in
            SingleRingEntryView(entry: entry)
        }
        .configurationDisplayName("QuotaRing · Single")
        .description("One battery-style ring for your chosen AI provider.")
        .supportedFamilies([.systemSmall])
    }
}

struct DualRingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "app.solocraft.quotaring.dual",
            intent: SelectDualProviderIntent.self,
            provider: DualRingProvider()
        ) { entry in
            DualRingEntryView(entry: entry)
        }
        .configurationDisplayName("QuotaRing · Dual")
        .description("Two battery-style rings for one multi-window provider (GLM, Kimi Code, MiniMax 5h + 7d).")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct QuotaRingWidgetBundle: WidgetBundle {
    var body: some Widget {
        SingleRingWidget()
        DualRingWidget()
    }
}
