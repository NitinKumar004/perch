import Foundation
import ServiceManagement

/// Wraps "launch at login" via SMAppService (macOS 13+). Like notifications,
/// this needs a real app bundle — under `swift run` there's no bundle, so it
/// reports unavailable and the toggle is hidden.
@MainActor
enum LoginItem {
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Enable/disable launch at login. Returns whether it now matches `enabled`.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard isAvailable else { return false }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            return false
        }
    }
}
