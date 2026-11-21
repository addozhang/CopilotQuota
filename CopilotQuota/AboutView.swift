import SwiftUI
import AppKit

/// Custom About window (replaces the standard about panel) with links to the repo.
struct AboutView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("Copilot Quota")
                .font(.title2.bold())
            Text(L("Version %@", AppInfo.version))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Text(L("A tiny macOS widget for your GitHub Copilot quota."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let update = model.availableUpdate {
                Button(L("Download v%@", update.version)) {
                    NSWorkspace.shared.open(update.downloadURL)
                }
                .controlSize(.small)
                .linkCursor()
            } else if let status = model.updateStatusMessage {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(spacing: 10) {
                Button {
                    Task { await model.checkForUpdates(userInitiated: true) }
                } label: {
                    Label(L("Check for Updates"), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.link)
                .disabled(model.isCheckingUpdates)

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
