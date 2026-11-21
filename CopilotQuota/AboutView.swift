import SwiftUI
import AppKit

/// Custom About window (replaces the standard about panel) with links to the repo.
struct AboutView: View {
    @EnvironmentObject var coordinator: QuotaCoordinator

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("QuotaRing")
                .font(.title2.bold())
            Text(L("Version %@", AppInfo.version))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Text(L("Battery-style macOS menu bar & desktop widgets for your AI quotas."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let update = coordinator.availableUpdate {
                Button(L("Download v%@", update.version)) {
                    NSWorkspace.shared.open(update.downloadURL)
                }
                .controlSize(.small)
                .linkCursor()
            } else if let status = coordinator.updateStatusMessage {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(spacing: 10) {
                Button {
                    Task { await coordinator.checkForUpdates(userInitiated: true) }
                } label: {
                    Label(L("Check for Updates"), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.link)
                .disabled(coordinator.isCheckingUpdates)

                Link(destination: AppInfo.repoURL) {
                    Label(L("View on GitHub"), systemImage: "star")
                }
                Link(destination: AppInfo.issuesURL) {
                    Label(L("Report an issue"), systemImage: "exclamationmark.bubble")
                }
            }
            .font(.callout)
            .linkCursor()
        }
        .padding(28)
        .frame(width: 320)
    }
}
