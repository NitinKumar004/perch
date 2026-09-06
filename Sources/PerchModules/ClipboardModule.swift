import Foundation
import PerchCore
import PerchModuleKit
#if canImport(AppKit)
import AppKit
#endif

/// A snapshot of recent clipboard entries for rendering.
public struct ClipboardHistory: Sendable, Equatable {
    public var entries: [String]
    public static let empty = ClipboardHistory(entries: [])
    public init(entries: [String]) { self.entries = entries }
}

/// A fully local, on-device clipboard history. Watches the system pasteboard and
/// keeps the last few things you copied; the panel lists them and a click copies
/// one back to the clipboard. Nothing is ever persisted or sent anywhere.
///
/// The recorded history lives in a shared `ClipboardController` so the app can
/// write a chosen entry back to the pasteboard when its row is clicked (modules
/// stay pure and don't handle actions themselves).
public struct ClipboardModule: NotchModule {
    public typealias State = ClipboardHistory

    public static let descriptor = ModuleDescriptor(
        id: "system.clipboard",
        name: "Clipboard",
        summary: "Your recent copies, on-device — click one to copy it again.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false,
        detailFirst: true
    )

    private let controller: ClipboardController

    public init(controller: ClipboardController) {
        self.controller = controller
    }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<ClipboardHistory>> {
        let clock = context.clock
        let controller = controller
        let interval = context.refreshSeconds(fallback: 1, minimum: 1)

        return AsyncStream { continuation in
            let task = Task {
                var lastChangeCount = Self.currentChangeCount()
                // Seed with whatever's already on the pasteboard.
                if let text = Self.currentString() { await controller.record(text) }
                continuation.yield(Snapshot(value: ClipboardHistory(entries: await controller.snapshot()),
                                            freshness: .live, asOf: clock.now()))

                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(interval))
                    let change = Self.currentChangeCount()
                    if change != lastChangeCount {
                        lastChangeCount = change
                        if let text = Self.currentString() { await controller.record(text) }
                        continuation.yield(Snapshot(value: ClipboardHistory(entries: await controller.snapshot()),
                                                    freshness: .live, asOf: clock.now()))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: ClipboardHistory, in slot: Slot) -> PillFace {
        let count = value.entries.count
        return PillFace(text: count == 0 ? "clip" : "\(count)",
                        symbolName: "doc.on.clipboard", tint: .neutral,
                        tooltip: count == 0 ? "Clipboard history (empty)" : "\(count) recent copies")
    }

    public func detail(for value: ClipboardHistory) -> [DetailRow] {
        if value.entries.isEmpty {
            return [DetailRow(id: "clip-empty", title: "Nothing copied yet",
                              subtitle: "Copy something and it appears here.",
                              tint: .neutral, symbolName: "doc.on.clipboard")]
        }
        var rows = value.entries.enumerated().map { index, text in
            DetailRow(id: "clip-\(index)",
                      title: Self.preview(text),
                      subtitle: index == 0 ? "on the clipboard now" : "tap to copy",
                      tint: index == 0 ? .info : .neutral,
                      symbolName: "doc.on.doc",
                      action: "clip.copy:\(index)")
        }
        // A footer row to wipe the whole history.
        rows.append(DetailRow(id: "clip-clear", title: "Clear history",
                              tint: .neutral, symbolName: "trash",
                              action: "clip.clear:all"))
        return rows
    }

    /// A single-line, bounded preview so a huge copy doesn't blow out the row.
    static func preview(_ text: String, limit: Int = 60) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return oneLine.count > limit ? String(oneLine.prefix(limit)) + "…" : oneLine
    }

    private static func currentChangeCount() -> Int {
        #if canImport(AppKit)
        return NSPasteboard.general.changeCount
        #else
        return 0
        #endif
    }

    private static func currentString() -> String? {
        #if canImport(AppKit)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }
}
