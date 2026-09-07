import Foundation

/// A per-event token for alert ids. The notifier dedups alerts permanently by
/// `id`, so a rising-edge warning (good → hot, swap crossing heavy, disk filling)
/// must carry a distinct id each time it fires or the *second* episode is
/// silently swallowed. A seconds-resolution timestamp is unique enough — these
/// transitions are minutes apart — and gives every module one shared, honest way
/// to make an alert id fire once per episode.
public enum AlertEpisode {
    /// A token that changes each second, distinguishing one episode from the next.
    public static func token(now: Date = Date()) -> Int {
        Int(now.timeIntervalSince1970)
    }
}
