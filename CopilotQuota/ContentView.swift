import SwiftUI
import AppKit

enum ContentPresentation {
    case popover
    case window
}

struct ContentView: View {
    var presentation: ContentPresentation = .window

    @EnvironmentObject var coordinator: QuotaCoordinator
    @Environment(\.openWindow) private var openWindow

    @State private var showingAddProvider = false
    @State private var editingAccount: ProviderAccount?
    @State private var quickAddKind: ProviderKind?

    var body: some View {
        VStack(spacing: 12) {
            if showingAddProvider || editingAccount != nil || quickAddKind != nil {
                AddProviderView(
                    coordinator: coordinator,
                    editingAccount: editingAccount,
                    initialKind: quickAddKind,
                    onDismiss: {
                        showingAddProvider = false
                        editingAccount = nil
                        quickAddKind = nil
                    }
                )
            } else {
                dashboard
            }
        }
        .padding(presentation == .popover ? 16 : 20)
        .frame(width: presentation == .popover ? 344 : 390)
        .onAppear { coordinator.syncPreferences() }
    }

    private var dashboard: some View {
        VStack(spacing: 12) {
            header

            if coordinator.accounts.isEmpty {
                emptyState
            } else {
                accountsList
            }

            if let update = coordinator.availableUpdate {
                updateBanner(update)
            } else if let status = coordinator.updateStatusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            settingsSection

            Divider()

            footer
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("QuotaRing")
                .font(.headline)

            Spacer()

            Button {
                showingAddProvider = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help(L("Add Provider"))
            .linkCursor()

            if !coordinator.accounts.isEmpty {
                Button {
                    Task { await coordinator.refreshAll() }
                } label: {
                    if coordinator.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(coordinator.isRefreshing)
                .help(L("Refresh quota"))
                .linkCursor()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            QuotaRingView(presentation: .placeholder, kind: .copilot, size: 58)
                .padding(.top, 6)

            VStack(spacing: 4) {
                Text(L("Track your AI quotas in one place"))
                    .font(.subheadline.weight(.semibold))
                Text(L("Add your first provider to show battery-style rings in your menu bar and desktop widgets."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ProviderKind.allCases) { kind in
                    Button {
                        quickAddKind = kind
                    } label: {
                        HStack(spacing: 6) {
                            ProviderGlyphView(kind: kind, size: 14)
                            Text(kind.shortName)
                                .font(.caption.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .linkCursor()
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var accountsList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(coordinator.accounts) { account in
                    ProviderCardView(
                        account: account,
                        snapshot: coordinator.snapshots[account.id],
                        errorText: coordinator.accountErrors[account.id],
                        onRefresh: {
                            Task { await coordinator.refresh(account: account) }
                        },
                        onEdit: {
                            editingAccount = account
                        },
                        onRemove: {
                            coordinator.removeAccount(account)
                        }
                    )
                }
            }
        }
        .frame(maxHeight: 320)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Refresh interval"))
                    .font(.callout)
                Spacer()
                Picker(L("Refresh interval"), selection: Binding(
                    get: { coordinator.refreshInterval },
                    set: { coordinator.saveRefreshInterval($0) }
                )) {
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
                get: { coordinator.launchAtLogin },
                set: { coordinator.setLaunchAtLogin($0) }
            ))
            .font(.callout)
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(L("Show Dock icon"), isOn: Binding(
                get: { coordinator.showDockIcon },
                set: { coordinator.setShowDockIcon($0) }
            ))
            .font(.callout)
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                Task { await coordinator.checkForUpdates(userInitiated: true) }
            } label: {
                if coordinator.isCheckingUpdates {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(L("Check for Updates"))
                }
            }
            .buttonStyle(.link)
            .font(.caption)
            .disabled(coordinator.isCheckingUpdates)
            .linkCursor()

            Button(L("About")) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "about")
            }
            .buttonStyle(.link)
            .font(.caption)
            .linkCursor()

            Spacer()

            if presentation == .popover {
                Button(L("Quit")) { NSApp.terminate(nil) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .linkCursor()
            } else {
                Link(destination: AppInfo.repoURL) {
                    Label("GitHub", systemImage: "star")
                }
                .font(.caption)
                .linkCursor()
            }
        }
    }
}

// MARK: - Provider Card

struct ProviderCardView: View {
    let account: ProviderAccount
    let snapshot: ProviderSnapshot?
    let errorText: String?
    let onRefresh: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        let presentation = RingPresentation.from(snapshot: snapshot, account: account)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                QuotaRingView(presentation: presentation, kind: account.kind, size: 50)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(account.resolvedTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let plan = snapshot?.planLabel {
                            Text(plan)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(presentation.primaryText)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        if let secondary = presentation.secondaryText {
                            Text(secondary)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if let footerText = detailLine {
                        Text(footerText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Menu {
                    Button(L("Refresh quota"), action: onRefresh)
                    if account.kind != .copilot {
                        Button(L("Edit Provider"), action: onEdit)
                    } else {
                        Button(L("Reconnect GitHub"), action: onEdit)
                    }
                    Divider()
                    Button(L("Remove"), role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // Rolling windows breakdown (e.g. GLM 5h + Weekly).
            if case .rollingWindows(let windows) = snapshot?.metric, windows.count > 1 {
                VStack(spacing: 4) {
                    ForEach(windows) { window in
                        HStack(spacing: 6) {
                            Text(window.label)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .leading)
                            ProgressView(value: window.percentRemaining, total: 100)
                                .tint(RingPresentation.toneForPercent(window.percentRemaining).color)
                            Text("\(Int(window.percentRemaining.rounded()))%")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
                .padding(.top, 2)
            }

            if let errorText {
                Text(errorText)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private var detailLine: String? {
        guard let snapshot else { return L("Waiting for first refresh…") }
        switch snapshot.metric {
        case .metered(_, _, _, let resetAt, _):
            if let resetAt {
                let days = max(0, Int(ceil(resetAt.timeIntervalSinceNow / 86_400)))
                let dateStr = resetAt.formatted(date: .abbreviated, time: .omitted)
                return L("Resets %@ (%d d left)", dateStr, days)
            }
        case .rollingWindows(let windows):
            if let earliest = windows.compactMap(\.resetAt).min() {
                return L("Next reset %@", earliest.formatted(date: .omitted, time: .shortened))
            }
        case .balance:
            if let cap = account.balanceReferenceCap, cap > 0 {
                return L("Cap: %@%.0f", account.kind.defaultCurrencySymbol, cap)
            }
        }
        return L("Updated at %@", snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))
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
