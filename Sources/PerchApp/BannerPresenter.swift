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
    private let perCharacter: Double
    private let maxDwell: Double
    private var queue = BannerQueue()
    private var dismissTask: Task<Void, Never>?

    init(model: NotchViewModel, baseDwell: Double = 4.5, perCharacter: Double = 0.09, maxDwell: Double = 11) {
        self.model = model
        self.baseDwell = baseDwell
        self.perCharacter = perCharacter
        self.maxDwell = maxDwell
    }

    /// How long a banner stays. A long message marquees inside a fixed-width slot,
    /// so a flat dwell showed only the start before vanishing ("half shown and
    /// gone"). Scale the dwell with the message length — capped — so the scroll
    /// has time to reveal the whole thing, while a short banner stays brief.
    nonisolated static func dwell(textLength: Int, base: Double, perCharacter: Double, max: Double) -> Double {
        Swift.min(max, base + Double(Swift.max(0, textLength)) * perCharacter)
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
                               base: baseDwell, perCharacter: perCharacter, max: maxDwell)
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
