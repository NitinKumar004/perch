import Foundation
import UserNotifications
import PerchModuleKit
import PerchConfig

/// Posts native macOS notifications for module alerts, deduped by alert id so
/// the same event never nags twice. Authorization is requested once at launch;
/// if the user declines, posting is a silent no-op.
@MainActor
final class Notifier {
    // Bounded dedup: a Set for O(1) lookup + an insertion-order queue so the
    // oldest ids are evicted once the cap is hit. Without the cap this would
    // grow forever in a long-running background agent.
    private var seen = Set<String>()
    private var order: [String] = []
    private let maxRemembered = 500

    /// Quiet-hours policy — during the window, alerts are recorded (so they
    /// never surface late in a burst) but not posted. Updated from config.
    private var global = GlobalSettings()

    /// Apply the latest global settings (e.g. quiet hours) from config.
    func configure(_ global: GlobalSettings) { self.global = global }

    /// `UNUserNotificationCenter` requires a real app bundle with an identifier.
    /// Running the bare executable (`swift run`) has none and would crash, so we
    /// no-op there — notifications work in the installed Perch.app.
    private var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Post an alert unless one with the same id has already been shown — or
    /// we're inside quiet hours, in which case it's remembered but never posted.
    func post(_ alert: ModuleAlert) {
        guard !seen.contains(alert.id) else { return }
        remember(alert.id)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        guard !global.isQuiet(minuteOfDay: minute) else { return }
        guard isAvailable else { return }

        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default

        let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func remember(_ id: String) {
        seen.insert(id)
        order.append(id)
        if order.count > maxRemembered {
            let evicted = order.removeFirst()
            seen.remove(evicted)
        }
    }
}
