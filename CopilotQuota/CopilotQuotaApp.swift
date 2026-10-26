import SwiftUI

@main
struct CopilotQuotaApp: App {
    var body: some Scene {
        // Single-window scene: repeated widget clicks (copilotquota://open)
        // focus the existing window instead of stacking new ones.
        Window("Copilot Quota", id: "main") {
            ContentView()
                .frame(width: 420, height: 480)
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
