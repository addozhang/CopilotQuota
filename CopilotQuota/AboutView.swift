import SwiftUI
import AppKit

/// Custom About window (replaces the standard about panel) with links to the repo.
struct AboutView: View {
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

            Divider()

            VStack(spacing: 10) {
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
