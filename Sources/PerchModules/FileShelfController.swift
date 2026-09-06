import Foundation

/// One stashed item on the shelf: a file's path plus its display name.
public struct ShelfItem: Sendable, Equatable {
    public var path: String
    public var name: String
    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }
}

/// The on-device file shelf: a small, ordered stash of file paths the user
/// dropped onto the panel, so a file is one drag away from any Finder window or
/// a chat. Paths only — nothing is copied or uploaded — honouring "local only".
///
/// Shared like the other controllers so the shell can record a drop while the
/// module reads the current shelf to render it.
public actor FileShelfController {
    private var items: [ShelfItem] = []   // most-recent first
    private let cap: Int

    public init(cap: Int = 10) { self.cap = cap }

    /// Add a dropped path. De-dupes by path (an existing one moves to the top)
    /// and caps the shelf so it can't grow without bound.
    public func add(path: String) {
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty else { return }
        items.removeAll { $0.path == path }
        items.insert(ShelfItem(path: path, name: name), at: 0)
        if items.count > cap { items.removeLast(items.count - cap) }
    }

    public func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
    }

    public func snapshot() -> [ShelfItem] { items }

    public func item(at index: Int) -> ShelfItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    public func clear() { items.removeAll() }
}
