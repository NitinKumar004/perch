import Foundation

/// The math behind the build activity's *learned* ETA — pure, so the prediction
/// and the countdown are unit-testable without a network or a clock.
///
/// A CI run's finish time is predicted from how long *your own* past runs of that
/// workflow took (the median, which shrugs off one unusually slow run), turning a
/// static "running" dot into a real "≈4m left" countdown. No history yet → we
/// show elapsed only and never invent a number.
public enum RunHistory {
    /// The middle value (even count → mean of the two middle) — a robust central
    /// estimate that a single outlier can't drag around. nil for an empty list.
    public static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[mid] }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// The predicted total run duration in seconds from past completed durations,
    /// or nil when there's nothing to learn from yet.
    public static func predict(durations: [Int]) -> Int? {
        median(durations.filter { $0 > 0 })
    }

    /// Progress 0…1 for the pill bar: elapsed vs the prediction, clamped so an
    /// overrun caps the bar at full. nil when there's no prediction to divide by.
    public static func progress(elapsedSeconds: Int, predictedSeconds: Int?) -> Double? {
        guard let predicted = predictedSeconds, predicted > 0 else { return nil }
        return Swift.min(1, Swift.max(0, Double(elapsedSeconds) / Double(predicted)))
    }

    /// The glanceable countdown: "≈4m left" from the prediction, "running 3m" when
    /// there's no history to predict from, or "overdue +2m" once it's run past the
    /// estimate. `showETA == false` always yields the plain elapsed form.
    public static func etaText(elapsedSeconds: Int, predictedSeconds: Int?, showETA: Bool = true) -> String {
        let elapsed = Swift.max(0, elapsedSeconds)
        guard showETA, let predicted = predictedSeconds, predicted > 0 else {
            return "running \(minutes(elapsed))"
        }
        let remaining = predicted - elapsed
        if remaining >= 0 { return "≈\(minutes(remaining)) left" }
        return "overdue +\(minutes(-remaining))"
    }

    /// Compact "Xm"/"Xs" for a duration in seconds (whole minutes above a minute).
    static func minutes(_ seconds: Int) -> String {
        let s = Swift.max(0, seconds)
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m"
    }
}
