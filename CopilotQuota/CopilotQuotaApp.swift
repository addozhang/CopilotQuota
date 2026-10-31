import SwiftUI

@main
struct CopilotQuotaApp: App {
    // App-level model: the auto-refresh timer must survive closing the
    // window (the process keeps running until Cmd-Q), otherwise quota and
    // token staleness return as soon as the window is closed.
    @StateObject private var model = AppModel()

    var body: some Scene {
        // Single-window scene: repeated widget clicks (copilotquota://open)
        // focus the existing window instead of stacking new ones.
        Window("Copilot Quota", id: "main") {
            ContentView()
                .frame(width: 420, height: 480)
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
        .commands {
            AppCommands()
        }

        Window(L("About Copilot Quota"), id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L("About Copilot Quota")) {
                openWindow(id: "about")
            }
            .keyboardShortcut("i", modifiers: [.command])
        }
    }
}
