import Foundation
import PerchCore
import PerchModuleKit

/// The shelf's state for rendering.
public struct ShelfState: Sendable, Equatable {
    public var items: [ShelfItem]
    public static let empty = ShelfState(items: [])
    public init(items: [ShelfItem]) { self.items = items }
}

/// A drag-and-drop file shelf. Drop files onto the panel and they land here;
/// click one to reveal it in Finder, or drag it back out into any app. Stores
/// paths only — nothing is copied or uploaded.
///
/// The dropped items live in a shared `FileShelfController` (the panel's drop
/// handler writes to it); this module reads it and renders rows.
public struct FileShelfModule: NotchModule {
    public typealias State = ShelfState

    public static let descriptor = ModuleDescriptor(
        id: "system.fileshelf",
        name: "Shelf",
        summary: "Drop files here to stash them — click to reveal in Finder.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    private let controller: FileShelfController

    public init(controller: FileShelfController) {
        self.controller = controller
    }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<ShelfState>> {
        let clock = context.clock
        let controller = controller
        let interval = context.refreshSeconds(fallback: 1, minimum: 1)
        return AsyncStream { continuation in
            let task = Task {
                var last: [ShelfItem] = []
                // Emit immediately, then only when the shelf actually changes.
                while !Task.isCancelled {
                    let items = await controller.snapshot()
                    if items != last {
                        last = items
                        continuation.yield(Snapshot(value: ShelfState(items: items),
                                                    freshness: .live, asOf: clock.now()))
                    }
                    try? await Task.sleep(for: .seconds(interval))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: ShelfState, in slot: Slot) -> PillFace {
        let count = value.items.count
        return PillFace(text: count == 0 ? "shelf" : "\(count)",
                        symbolName: "tray.full", tint: .neutral,
                        tooltip: count == 0 ? "File shelf (drop files onto the panel)" : "\(count) files on the shelf")
    }

    public func detail(for value: ShelfState) -> [DetailRow] {
        if value.items.isEmpty {
            return [DetailRow(id: "shelf-empty", title: "Drop files onto this panel",
                              subtitle: "They stash here — click to reveal in Finder.",
                              tint: .neutral, symbolName: "tray.and.arrow.down")]
        }
        return value.items.enumerated().map { index, item in
            DetailRow(id: "shelf-\(index)",
                      title: item.name,
                      subtitle: Self.shortPath(item.path),
                      tint: .info,
                      symbolName: "doc",
                      action: "shelf.open:\(index)",
                      secondaryAction: "shelf.remove:\(index)",
                      secondaryIcon: "xmark.circle.fill")
        }
    }

    /// Abbreviate a long path to its last two components so the row stays tidy.
    static func shortPath(_ path: String, keep: Int = 2) -> String {
        let parts = path.split(separator: "/")
        guard parts.count > keep else { return path }
        return "…/" + parts.suffix(keep).joined(separator: "/")
    }
}
