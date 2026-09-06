import Foundation

/// Watches the config file for external edits and fires a callback so the notch
/// re-wires itself the moment you save `layout.json` in an editor — no manual
/// "Reload" needed.
///
/// It polls the file's modification date on a light timer rather than using a
/// kernel file-event source, because the config is written atomically (the file
/// is replaced, not edited in place), which invalidates a file-descriptor watch.
/// Polling an mtime survives the replace and is trivially correct.
@MainActor
final class ConfigWatcher {
    private let fileURL: URL
    private let onChange: () -> Void
    private var timer: Timer?
    private var lastModified: Date?

    init(fileURL: URL, onChange: @escaping () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
    }

    /// Start polling. Records the current mtime as the baseline so the first
    /// external edit — not the app's own startup — is what triggers a reload.
    func start() {
        lastModified = modifiedDate()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Re-baseline to the file's current mtime. The shell calls this right after
    /// it applies the config itself (launch, Settings save), so its own writes
    /// don't bounce back as an "external" change.
    func markApplied() {
        lastModified = modifiedDate()
    }

    private func tick() {
        let current = modifiedDate()
        guard current != lastModified else { return }
        lastModified = current
        onChange()
    }

    private func modifiedDate() -> Date? {
        try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
    }
}
