import Foundation
import UserNotifications
import PerchModuleKit

/// Posts native macOS notifications for module alerts, deduped by alert id so
/// the same event never nags twice. Authorization is requested once at launch;
/// if the user declines, posting is a silent no-op.
@MainActor
final class Notifier {
    private var seen = Set<String>()

    /// `UNUserNotificationCenter` requires a real app bundle with an identifier.
    /// Running the bare executable (`swift run`) has none and would crash, so we
    /// no-op there — notifications work in the installed Perch.app.
    private var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Post an alert unless one with the same id has already been shown.
    func post(_ alert: ModuleAlert) {
        guard isAvailable, !seen.contains(alert.id) else {
            seen.insert(alert.id)  // still remember it, so it never fires later
            return
        }
        seen.insert(alert.id)

        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default

        let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
