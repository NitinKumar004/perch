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
    private let dwell: Double
    private var queue = BannerQueue()
    private var dismissTask: Task<Void, Never>?

    init(model: NotchViewModel, dwellSeconds: Double = 4) {
        self.model = model
        self.dwell = dwellSeconds
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
        dismissTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.dwell))
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
