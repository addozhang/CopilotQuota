import SwiftUI
import AppKit

/// First-run login: GitHub OAuth Device Flow.
struct DeviceFlowView: View {
    @ObservedObject var model: AppModel

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
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.06))
                CopilotIconShape().fill(.primary).frame(width: 44, height: 44)
            }
            .frame(width: 72, height: 72)

            VStack(spacing: 4) {
                Text("Copilot Quota")
                    .font(.title3.bold())
                Text(L("Sign in to GitHub to read your Copilot quota"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

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
                        .foregroundStyle(.secondary)
                }

            case .code(let userCode, let url, let minutes):
                codeEntry(userCode: userCode, url: url, minutes: minutes)

            case .failed(let message):
                VStack(spacing: 12) {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button(L("Retry")) { startFlow() }
                        .controlSize(.large)
                        .linkCursor()
                }
            }

            Spacer()

            Link(destination: AppInfo.repoURL) {
                Label("GitHub", systemImage: "star")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .linkCursor()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { flowTask?.cancel() }
    }

    @ViewBuilder
    private func codeEntry(userCode: String, url: URL, minutes: Int) -> some View {
        VStack(spacing: 14) {
            Text(L("1. Enter this code on the page"))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text(userCode)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .kerning(3)
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
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            Text(L("2. If the page didn't open, click below"))
                .font(.callout)
                .foregroundStyle(.secondary)

            Button(L("Open github.com/login/device")) {
                NSWorkspace.shared.open(url)
            }
            .linkCursor()

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("Waiting for authorization — valid for %d min…", minutes))
                    .font(.caption)
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
                SharedStore.storeTokenPair(accessToken: pair.accessToken,
                                           refreshToken: pair.refreshToken,
                                           expiresInSeconds: pair.expiresInSeconds)
                model.token = pair.accessToken
                // The post-login refresh must survive the view switch: once
                // model.token is set this view disappears and onDisappear
                // cancels flowTask — so refresh in a fresh task instead.
                Task { await model.refresh() }
            } catch is CancellationError {
                // Flow cancelled (view dismissed); nothing to do.
            } catch let urlError as URLError where urlError.code == .cancelled {
                // URLSession surfaces task cancellation as URLError.cancelled.
            } catch {
                withAnimation { phase = .failed(error.localizedDescription) }
            }
        }
    }
}
