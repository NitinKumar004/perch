import Foundation
import Observation
import PerchModuleKit

/// The single source of UI truth for the notch surface. The composition root
/// feeds it `PillContent` as modules produce it; SwiftUI re-renders only the
/// pill that actually changed.
///
/// `@Observable` + `@MainActor`: reads are cheap and updates are always applied
/// on the main thread, so the UI never races with a background provider.
@MainActor
@Observable
public final class NotchViewModel {
    public var leftPill: PillContent?
    public var rightPill: PillContent?

    public init() {}
}
