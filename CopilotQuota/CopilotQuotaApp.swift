import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDockPolicy(showDockIcon: SharedStore.showDockIcon)

        // When launched in default pure Menu Bar mode and already signed in,
        // keep startup quiet in the menu bar without flashing a window.
        if SharedStore.token != nil && !SharedStore.showDockIcon {
            DispatchQueue.main.async {
                for window in NSApp.windows where window.identifier?.rawValue == "main" {
                    window.close()
                }
            }
        } else if SharedStore.token == nil {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func applyDockPolicy(showDockIcon: Bool) {
        let target: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != target {
            NSApp.setActivationPolicy(target)
        }
        if showDockIcon {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

/// Renders `CopilotIconShape` into a crisp macOS template `NSImage` for `MenuBarExtra`.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size, flipped: true) { rect in
            let inset = rect.insetBy(dx: 0.5, dy: 0.5)
            let cgPath = CopilotIconShape().path(in: inset).cgPath
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(cgPath)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            return true
        }
        img.isTemplate = true
        return img
    }()
}

@main
struct CopilotQuotaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // App-level model: the auto-refresh timer must survive closing the
    // window (and runs continuously in Menu Bar mode), keeping quota and
    // OAuth tokens fresh without hitting WidgetKit's daily budget.
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView(presentation: .popover)
                .environmentObject(model)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: MenuBarIcon.image)
                if let label = model.menuBarPercentText {
                    Text(label)
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        // Single-window scene: repeated widget clicks (copilotquota://open)
        // focus the existing window instead of stacking new ones.
        Window("Copilot Quota", id: "main") {
            ContentView(presentation: .window)
                .environmentObject(model)
                .onOpenURL { _ in
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentSize)
        .commands {
            AppCommands(model: model)
        }

        Window(L("About Copilot Quota"), id: "about") {
            AboutView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
    }
}

struct AppCommands: Commands {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L("About Copilot Quota")) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "about")
            }
            .keyboardShortcut("i", modifiers: [.command])

            Button(L("Check for Updates…")) {
                Task { await model.checkForUpdates(userInitiated: true) }
            }
        }
    }
}
