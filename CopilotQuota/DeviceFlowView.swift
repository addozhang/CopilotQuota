import SwiftUI
import AppKit

/// GitHub OAuth Device Flow view used when connecting a Copilot account.
struct DeviceFlowView: View {
    @ObservedObject var coordinator: QuotaCoordinator
    var onComplete: () -> Void
    var onCancel: () -> Void

    enum Phase: Equatable {
        case idle
        case requesting
        case code(userCode: String, verificationURL: URL, expiresInMinutes: Int)
        case failed(String)
    }

    @State private var phase: Phase = .idle
    @State private var flowTask: Task<Void, Never>?
    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.06))
                CopilotIconShape().fill(.primary).frame(width: 34, height: 34)
            }
            .frame(width: 56, height: 56)

            VStack(spacing: 4) {
                Text("GitHub Copilot")
                    .font(.headline)
                Text(L("Sign in to GitHub to read your Copilot quota"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            switch phase {
            case .idle:
                Button {
                    startFlow()
                } label: {
                    Label(L("Sign in with GitHub"), systemImage: "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .linkCursor()

            case .requesting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Requesting device code…"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

            case .code(let userCode, let url, let minutes):
                codeEntry(userCode: userCode, url: url, minutes: minutes)

            case .failed(let message):
                VStack(spacing: 10) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button(L("Retry")) { startFlow() }
                        .controlSize(.regular)
                        .linkCursor()
                }
            }

            Button(L("Back")) {
                flowTask?.cancel()
                onCancel()
            }
            .buttonStyle(.link)
            .font(.caption)
            .foregroundStyle(.secondary)
            .linkCursor()
        }
        .padding(.vertical, 8)
        .onDisappear { flowTask?.cancel() }
    }

    @ViewBuilder
    private func codeEntry(userCode: String, url: URL, minutes: Int) -> some View {
        VStack(spacing: 10) {
            Text(L("1. Enter this code on the page"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text(userCode)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .kerning(2)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(userCode, forType: .string)
                    copied = true
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help(L("Copy code"))
                .linkCursor()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            Text(L("2. If the page didn't open, click below"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(L("Open github.com/login/device")) {
                NSWorkspace.shared.open(url)
            }
            .controlSize(.small)
            .linkCursor()

            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(L("Waiting for authorization — valid for %d min…", minutes))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func startFlow() {
        flowTask?.cancel()
        copied = false
        phase = .requesting
        flowTask = Task {
            do {
                let flow = GitHubDeviceFlow()
                let code = try await flow.requestDeviceCode()
                guard !Task.isCancelled else { return }
                let urlString = code.verificationUriComplete ?? code.verificationUri
                let url = URL(string: urlString) ?? URL(string: "https://github.com/login/device")!
                withAnimation {
                    phase = .code(userCode: code.userCode,
                                  verificationURL: url,
                                  expiresInMinutes: max(1, code.expiresIn / 60))
                }
                NSWorkspace.shared.open(url)

                let pair = try await flow.waitForToken(deviceCode: code.deviceCode,
                                                       interval: code.interval,
                                                       expiresIn: code.expiresIn)
                guard !Task.isCancelled else { return }
                coordinator.addCopilotAccount(pair: pair)
                onComplete()
            } catch is CancellationError {
                // Cancelled
            } catch let urlError as URLError where urlError.code == .cancelled {
                // Cancelled
            } catch {
                withAnimation { phase = .failed(error.localizedDescription) }
            }
        }
    }
}
