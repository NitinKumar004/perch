import AppKit
import UserNotifications

/// What to play when an alert is delivered — resolved purely from the user's
/// `notificationSound` setting, so the decision is unit-testable without audio.
enum AlertSound: Equatable {
    case silent
    case systemDefault
    case named(String)

    /// The named system sounds offered in Settings (macOS's built-in alert sounds
    /// under /System/Library/Sounds). This is also the pick-list order.
    static let systemSoundNames = [
        "Ping", "Glass", "Hero", "Sosumi", "Submarine", "Funk",
        "Blow", "Bottle", "Frog", "Morse", "Pop", "Purr", "Tink", "Basso",
    ]

    /// Map the stored setting to a decision. "none" → silent; "default"/empty →
    /// the OS default sound (the original behaviour); a KNOWN name → that sound;
    /// an unrecognised value falls back to the audible default rather than going
    /// silently wrong.
    static func resolve(_ setting: String) -> AlertSound {
        switch setting {
        case "none": return .silent
        case "", "default": return .systemDefault
        default: return systemSoundNames.contains(setting) ? .named(setting) : .systemDefault
        }
    }

    /// The sound the OS notification itself should carry: the default sound for
    /// `.systemDefault`, and nil for `.silent` and `.named` — a named sound is
    /// played by the app directly, so the OS notification stays silent to avoid a
    /// double chime. Pure, so the mapping is unit-testable.
    var osNotificationSound: UNNotificationSound? {
        switch self {
        case .systemDefault: return .default
        case .silent, .named: return nil
        }
    }
}

/// The sound-playing seam, so `Notifier` is testable without real audio — the
/// same injectable-system-dependency shape as `CalendarReading`/`PasteboardReading`.
@MainActor protocol AlertSoundPlaying {
    func play(_ sound: AlertSound)
}

/// Production player. `.named` plays that system sound via `NSSound`;
/// `.systemDefault` plays the system alert beep (used by the Settings preview —
/// during real delivery the OS notification plays the default sound itself, so
/// the caller doesn't ask the player to); `.silent` does nothing.
///
/// A class (not a struct) because `NSSound.play()` is asynchronous: the instance
/// holds a strong reference to the currently-playing sound until it finishes, so
/// ARC can't deallocate it out from under playback and cut it off — the classic
/// AppKit gotcha. The player is long-lived (owned by `Notifier`, and by the
/// Settings view across selections), so the retained sound survives to the end.
@MainActor final class SystemAlertSoundPlayer: NSObject, AlertSoundPlaying, NSSoundDelegate {
    private var current: NSSound?

    func play(_ sound: AlertSound) {
        switch sound {
        case .silent:
            break
        case .systemDefault:
            NSSound.beep()
        case .named(let name):
            guard let sound = NSSound(named: NSSound.Name(name)) else { return }
            sound.delegate = self
            current = sound          // retain until playback finishes
            sound.play()
        }
    }

    nonisolated func sound(_ sound: NSSound, didFinishPlaying finished: Bool) {
        // Identify the finished sound by a Sendable id (the NSSound itself isn't
        // Sendable), then release our retain if it's still the current one.
        let finishedID = ObjectIdentifier(sound)
        Task { @MainActor [weak self] in
            guard let self, let current = self.current,
                  ObjectIdentifier(current) == finishedID else { return }
            self.current = nil
        }
    }
}
