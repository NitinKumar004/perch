import AppKit
import Foundation
import PerchNotchUI

/// Drives the transient in-notch banner: shows one at a time in the pill row,
/// auto-dismisses after a dwell, then shows the next queued one. The ordering
/// lives in the pure `BannerQueue`; this adds the timing and the view-model
/// wiring. (The banner renders in-place in the existing bar, so no window
/// resize is involved.)
@MainActor
final class BannerPresenter {
    private let model: NotchViewModel
    private let baseDwell: Double
    private let maxDwell: Double
    private var queue = BannerQueue()
    private var dismissTask: Task<Void, Never>?

    init(model: NotchViewModel, baseDwell: Double = 3.5, maxDwell: Double = 20) {
        self.model = model
        self.baseDwell = baseDwell
        self.maxDwell = maxDwell
    }

    /// How long a banner stays. A long message marquees inside a fixed-width slot,
    /// so the dwell is DERIVED from the marquee's own cycle (hold + scroll + end
    /// pause, from `MarqueeTiming`) plus a small tail — guaranteeing the whole
    /// message reveals once before it dismisses, instead of a flat cap racing the
    /// scroll. A short message that fits (no scroll) just uses the base dwell.
    /// `max` bounds a pathological run-on so it can't linger forever. Under Reduce
    /// Motion the banner never scrolls (the text truncates), so there's nothing to
    /// wait for — it uses the base dwell instead of a long scroll-assuming one.
    nonisolated static func dwell(textLength: Int, base: Double, max: Double, reduceMotion: Bool = false) -> Double {
        guard !reduceMotion else { return base }
        let reveal = MarqueeTiming.bannerRevealSeconds(textLength: textLength)
        let needed = reveal > 0 ? reveal + 1.0 : base
        return Swift.min(max, Swift.max(base, needed))
    }

    /// The text the banner actually renders (title, plus body when present) —
    /// the length that drives the dwell, matching BannerView's own composition.
    nonisolated static func displayText(_ banner: BannerAlert) -> String {
        banner.body.isEmpty ? banner.title : "\(banner.title) · \(banner.body)"
    }

    /// Show a banner (or queue it behind the current one).
    func show(_ banner: BannerAlert) {
        if queue.enqueue(banner) { present(banner) }
    }

    /// Dismiss the current banner early (e.g. the user opened the panel),
    /// advancing to the next queued one.
    func dismissCurrent() {
        dismissTask?.cancel()
        advance()
    }

    private func present(_ banner: BannerAlert) {
        model.banner = banner
        dismissTask?.cancel()
        let dwell = Self.dwell(textLength: Self.displayText(banner).count,
                               base: baseDwell, max: maxDwell,
                               reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        dismissTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(dwell))
            guard !Task.isCancelled else { return }
            self.advance()
        }
    }

    private func advance() {
        if let next = queue.advance() {
            present(next)
        } else {
            model.banner = nil
        }
    }
}
