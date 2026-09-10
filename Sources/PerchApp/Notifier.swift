import AppKit
import Foundation
import UserNotifications
import PerchModuleKit
import PerchConfig

/// Posts native macOS notifications for module alerts, deduped by alert id so
/// the same event never nags twice. Authorization is requested once at launch;
/// if the user declines, posting is a silent no-op.
///
/// Also the notification-center delegate, so tapping an alert opens the URL the
/// module attached (the failing build, the PR waiting on review).
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    // Bounded dedup: a Set for O(1) lookup + an insertion-order queue so the
    // oldest ids are evicted once the cap is hit. Without the cap this would
    // grow forever in a long-running background agent.
    private var seen = Set<String>()
    private var order: [String] = []
    private let maxRemembered = 500

    /// Quiet-hours policy — during the window, alerts are recorded (so they
    /// never surface late in a burst) but not posted. Updated from config.
    private var global = GlobalSettings()

    /// Plays a chosen alert sound. Injected so delivery is testable without audio.
    private let soundPlayer: any AlertSoundPlaying

    init(soundPlayer: any AlertSoundPlaying = SystemAlertSoundPlayer()) {
        self.soundPlayer = soundPlayer
        super.init()
    }

    /// Apply the latest global settings (e.g. quiet hours, alert sound) from config.
    func configure(_ global: GlobalSettings) { self.global = global }

    /// `UNUserNotificationCenter` requires a real app bundle with an identifier.
    /// Running the bare executable (`swift run`) has none and would crash, so we
    /// no-op there — notifications work in the installed Perch.app.
    private var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().delegate = self
        Self.askForAuthorization()
    }

    /// The permission prompt's completion runs on a background queue. If the
    /// closure inherits this `@MainActor` type's isolation, Swift 6's runtime
    /// executor check traps (SIGTRAP) and crashes the app on launch. Issuing the
    /// request from a `nonisolated static` keeps the completion actor-free.
    private nonisolated static func askForAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Tapping a notification opens the URL the alert carried, if any.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let urlString = response.notification.request.content.userInfo["url"] as? String
        completionHandler()
        if let urlString {
            Task { @MainActor in
                if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
            }
        }
    }

    /// Show the banner even while Perch is frontmost (it's a background agent, so
    /// this is the norm), otherwise alerts would be silently dropped.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Post an alert unless one with the same id has already been shown — or
    /// we're inside quiet hours, in which case it's remembered but never posted.
    /// The outcome of trying to post an alert — lets the caller mirror it to the
    /// in-notch banner only when it was actually delivered (not a duplicate, not
    /// during quiet hours).
    enum AlertOutcome { case delivered, duplicate, quiet }

    /// Whether we're currently inside the user's quiet-hours window.
    private var isQuietNow: Bool {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        return global.isQuiet(minuteOfDay: minute)
    }

    /// Play the configured alert sound for an event that ISN'T a posted native
    /// notification — e.g. the auto-open "why" banner — so ANY surfacing alert is
    /// audible, not just posted notifications. Honours quiet hours; "none" is
    /// silent, "default" plays the system beep, a named sound plays that.
    func playConfiguredSound() {
        guard !isQuietNow else { return }
        let sound = AlertSound.resolve(global.notificationSound)
        if sound != .silent { soundPlayer.play(sound) }
    }

    @discardableResult
    func post(_ alert: ModuleAlert) -> AlertOutcome {
        guard !seen.contains(alert.id) else { return .duplicate }
        remember(alert.id)
        guard !isQuietNow else { return .quiet }

        // Sound policy: a chosen NAMED sound we play ourselves, so it's heard even
        // when Focus/DND is suppressing the OS banner; the default sound rides on
        // the OS notification below; "none" is silent. (Quiet hours already
        // returned above, so this only runs when the user should be alerted.)
        let sound = AlertSound.resolve(global.notificationSound)
        if case .named = sound { soundPlayer.play(sound) }

        // The macOS banner needs a real bundle; the in-notch banner (the caller's
        // job on `.delivered`) does not — so report delivered either way.
        if isAvailable {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = sound.osNotificationSound   // .default for default, nil for silent/named
            if let url = alert.url { content.userInfo["url"] = url }
            let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
        return .delivered
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
