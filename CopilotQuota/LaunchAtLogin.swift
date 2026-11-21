import Foundation
import ServiceManagement
import os

private let loginLog = Logger(subsystem: "app.solocraft.copilotquota", category: "login-item")

/// Thin wrapper over `SMAppService.mainApp` for Launch at Login (macOS 13+).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return isEnabled
        } catch {
            loginLog.error("Failed to update Launch at Login (\(enabled)): \(error.localizedDescription, privacy: .public)")
            return isEnabled
        }
    }
}
