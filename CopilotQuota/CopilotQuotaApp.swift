import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = SharedSnapshotStore.shared
        applyDockPolicy(showDockIcon: store.showDockIcon)

        // When launched in default pure Menu Bar mode and at least one provider
        // is already configured, stay quietly in the menu bar without flashing a window.
        if !store.accounts.isEmpty && !store.showDockIcon {
            DispatchQueue.main.async {
                for window in NSApp.windows where window.identifier?.rawValue == "main" {
                    window.close()
                }
            }
        } else if store.accounts.isEmpty {
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

/// Renders QuotaRing's minimal battery-ring template icon for `MenuBarExtra`.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 6.2
            let lineWidth: CGFloat = 1.9

            // Outer track arc (subtle) + active 3/4 ring
            ctx.setLineCap(.round)
            ctx.setLineWidth(lineWidth)

            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.32).cgColor)
            ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.strokePath()

            ctx.setStrokeColor(NSColor.black.cgColor)
            let start: CGFloat = -.pi / 2
            let end: CGFloat = start + .pi * 1.55
            ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            ctx.strokePath()

            // Tiny center dot
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - 1.8, y: center.y - 1.8, width: 3.6, height: 3.6))
            return true
        }
        img.isTemplate = true
        return img
    }()
}

@main
struct QuotaRingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var coordinator = QuotaCoordinator()

    var body: some Scene {
        // Icon-only Menu Bar entry: zero horizontal clutter, click for full multi-provider popover.
        MenuBarExtra {
            ContentView(presentation: .popover)
                .environmentObject(coordinator)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)

        // Single-window scene: widget clicks (quotaring://open or legacy copilotquota://open)
        // focus the existing window instead of stacking new ones.
        Window("QuotaRing", id: "main") {
            ContentView(presentation: .window)
                .environmentObject(coordinator)
                .onOpenURL { _ in
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentSize)
        .commands {
            AppCommands(coordinator: coordinator)
        }

        Window(L("About QuotaRing"), id: "about") {
            AboutView()
                .environmentObject(coordinator)
        }
        .windowResizability(.contentSize)
    }
}

struct AppCommands: Commands {
    @ObservedObject var coordinator: QuotaCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L("About QuotaRing")) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "about")
            }
            .keyboardShortcut("i", modifiers: [.command])

            Button(L("Check for Updates…")) {
                Task { await coordinator.checkForUpdates(userInitiated: true) }
            }
        }
    }
}
