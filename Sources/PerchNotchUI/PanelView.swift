import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PerchCore
import PerchModuleKit

/// Actions the panel footer can trigger, wired by the app. Keeping the controls
/// here means everything is reachable straight from the notch — no hunting for
/// the menu-bar icon.
public struct PanelActions: Sendable {
    public var onConnect: @MainActor () -> Void
    public var onSettings: @MainActor () -> Void
    public var onReload: @MainActor () -> Void
    public var onQuit: @MainActor () -> Void
    /// Handles a module's detail-row action (e.g. a timer's "timer.toggle:25").
    public var onAction: @MainActor (String) -> Void
    /// Handles files dropped onto the panel (the file shelf). Returns true if the
    /// drop was accepted, so the panel can show its highlight only when useful.
    public var onDropFiles: @MainActor ([URL]) -> Bool
    /// Reorder panel modules by drag: the new full order of panel-item ids. The
    /// shell reorders the live rows and persists the order to the active preset.
    public var onReorder: @MainActor (_ orderedIDs: [String]) -> Void
    /// The pointer entered (true) or left (false) the panel. Lets the shell pause
    /// an auto-open's auto-close countdown while you're reading it, and resume it
    /// when you move away.
    public var onHover: @MainActor (_ hovering: Bool) -> Void

    public init(onConnect: @escaping @MainActor () -> Void = {},
                onSettings: @escaping @MainActor () -> Void = {},
                onReload: @escaping @MainActor () -> Void = {},
                onQuit: @escaping @MainActor () -> Void = {},
                onAction: @escaping @MainActor (String) -> Void = { _ in },
                onDropFiles: @escaping @MainActor ([URL]) -> Bool = { _ in false },
                onReorder: @escaping @MainActor ([String]) -> Void = { _ in },
                onHover: @escaping @MainActor (Bool) -> Void = { _ in }) {
        self.onConnect = onConnect
        self.onSettings = onSettings
        self.onReload = onReload
        self.onQuit = onQuit
        self.onAction = onAction
        self.onDropFiles = onDropFiles
        self.onReorder = onReorder
        self.onHover = onHover
    }
}

/// The drop-down detail card that appears below the notch when opened. It lists
/// each configured panel module as a labelled row — the module's name, its
/// pill, and an honest freshness note — and a footer of controls. This is the
/// "report" + control surface.
struct PanelView: View {
    let items: [PanelItem]
    let isConnected: Bool
    let actions: PanelActions
    @State private var isDropTargeted = false
    @State private var draggingID: String?      // the section being dragged
    @State private var order: [String] = []     // working display order (live during a drag)
    @State private var expanded: Set<String> = []  // sections showing their full list
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            // Rows scroll if they exceed the panel height, so a rich panel (many
            // modules / a long PR list) never gets clipped.
            ScrollView {
                VStack(spacing: 0) {
                    rows
                }
            }
            .frame(maxHeight: 300)

            footer
        }
        .padding(.vertical, 4)
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.surface.opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(isDropTargeted ? palette.accent : palette.ink(0.08),
                                  lineWidth: isDropTargeted ? 2 : 1))
        )
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        // Pause an auto-open's auto-close countdown while the pointer is over the
        // panel (you're reading it), resume it when the pointer leaves.
        .onHover { actions.onHover($0) }
        // Drop files anywhere on the panel → the file shelf (if configured).
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            loadDroppedURLs(providers)
            return true
        }
        // Releasing a section anywhere over the panel commits the live order,
        // even if the cursor isn't over another row at that instant.
        .dropDestination(for: String.self) { _, _ in commitReorder(); return true }
        .onAppear { order = items.map(\.id) }
        .onChange(of: items.map(\.id)) { _, ids in
            // Adopt an external order change (config reload) when not mid-drag.
            if draggingID == nil { order = ids }
        }
    }

    /// Items in the current working order, with any not-yet-tracked rows appended.
    private var orderedItems: [PanelItem] {
        guard !order.isEmpty else { return items }
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var result = order.compactMap { byID[$0] }
        let known = Set(order)
        result.append(contentsOf: items.filter { !known.contains($0.id) })
        return result
    }

    /// Slide the dragged section to sit over `targetID`, live, so the other rows
    /// open a gap as the cursor moves — the premium reorder feel.
    private func liveMove(over targetID: String) {
        guard let moving = draggingID, moving != targetID else { return }
        let current = order.isEmpty ? items.map(\.id) : order
        let next = PanelReorder.reordered(current, moving: moving, target: targetID)
        guard next != current else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { order = next }
    }

    /// Persist whatever order the live drag settled on.
    private func commitReorder() {
        guard draggingID != nil else { return }
        draggingID = nil
        actions.onReorder(order.isEmpty ? items.map(\.id) : order)
    }

    /// Resolve dropped item providers to file URLs off the main actor, then hand
    /// them to the shell's drop handler.
    private func loadDroppedURLs(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in _ = actions.onDropFiles([url]) }
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(orderedItems) { item in
                section(item)
                Divider().overlay(palette.ink(0.06))
            }
            if items.isEmpty {
                Text("No panel modules configured")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.ink(0.4))
                    .padding(.vertical, 14)
            }
        }
    }

    /// One module's section (header + its detail rows). Reorderable sections can
    /// be dragged by their header; as a drag passes over other sections they
    /// slide to open a gap, and the dragged one dims until it's dropped.
    @ViewBuilder
    private func section(_ item: PanelItem) -> some View {
        let reorderable = isReorderable(item)
        let isDragging = draggingID == item.id
        VStack(spacing: 0) {
            // Header: module name (+ what it watches) and its pill.
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.ink(0.85))
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(palette.ink(0.45))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                headerTrailing(for: item)
            }
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, item.detail.isEmpty ? 9 : 4)
            .contentShape(Rectangle())
            // The header is the drag handle — dragging it never fights the
            // tappable links/buttons that live in the detail rows below.
            .ifReorderable(reorderable) { $0.onDrag {
                draggingID = item.id
                return NSItemProvider(object: item.id as NSString)
            } }

            // Detail rows. A row that merely restates the header (a single-metric
            // module's own summary) collapses to just its new payload — the
            // graph, and a subtitle the pill doesn't already say — so nothing is
            // stated twice. Genuinely informative rows (a meeting name, a PR, a
            // list) render full. A long list shows a short preview with a toggle.
            let isExpanded = expanded.contains(item.id)
            let shown = PanelCollapse.visibleCount(total: item.detail.count, expanded: isExpanded)
            if item.content.face.segments != nil {
                // A Combined section: its members are distinct metrics, so NEVER
                // collapse them to nameless charts (the de-dup rule that matches a
                // row title against the pill text misfires here, because the pill
                // text is every metric concatenated). Show each with its name +
                // value, laid out two per line so the section stays compact.
                combinedGrid(Array(item.detail.prefix(shown)))
            } else {
                ForEach(Array(item.detail.prefix(shown))) { row in
                    if isRedundantSummary(row, item: item) {
                        summaryStrip(row, pillText: item.content.face.text)
                    } else {
                        detailRow(row)
                    }
                }
            }
            if PanelCollapse.isCollapsible(total: item.detail.count) {
                expandToggle(id: item.id, total: item.detail.count, expanded: isExpanded)
            }
        }
        .opacity(isDragging ? 0.35 : 1)
        // Passing a drag over this section slides the dragged one into its place.
        .ifReorderable(reorderable) { $0.dropDestination(for: String.self) { _, _ in
            commitReorder(); return true
        } isTargeted: { targeted in
            if targeted { liveMove(over: item.id) }
        } }
    }

    /// A Combined section's metrics, two per line, each as its own little block:
    /// icon + name, the value, and — for CPU / memory and other trending metrics
    /// — the trend graph. Blocks keep every metric named and readable at a
    /// glance; the panel scrolls when there are more than fit.
    @ViewBuilder
    private func combinedGrid(_ rows: [DetailRow]) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 8, alignment: .top),
                      GridItem(.flexible(), spacing: 8, alignment: .top)],
            alignment: .leading, spacing: 8
        ) {
            ForEach(rows) { row in metricBlock(row) }
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    /// One metric block: name on top, then the value and its graph. The value
    /// wraps to a second line rather than truncating, so it's always readable.
    private func metricBlock(_ row: DetailRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if let symbol = row.symbolName {
                    Image(systemName: symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(tintColor(row.tint))
                }
                Text(row.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.ink(0.9))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(alignment: .bottom, spacing: 6) {
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.ink(0.6))
                        .lineLimit(2)                       // wraps, never cut off
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if let points = row.sparkline, points.count > 1 {
                    Sparkline(points: points, color: tintColor(row.tint))
                        .frame(width: 52, height: 18)
                } else if let progress = row.progress {
                    MiniBar(value: progress, color: tintColor(row.tint))
                        .frame(width: 52, height: 5)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.ink(0.05))
        )
    }

    /// The "Show all N / Show less" control for a long list, with an up/down
    /// chevron. Collapsed by default so a big list never dominates the panel.
    private func expandToggle(id: String, total: Int, expanded: Bool) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                if expanded { self.expanded.remove(id) } else { self.expanded.insert(id) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                Text(expanded ? "Show less" : "Show all \(total)")
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(palette.ink(0.5))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Only modules the user explicitly placed in the panel are reorderable —
    /// their id is "<module>#<index>". Rows auto-surfaced from a pill (id
    /// "<module>#pill-N") aren't in the saved panel list, so they stay put.
    private func isReorderable(_ item: PanelItem) -> Bool {
        guard let suffix = item.id.split(separator: "#").last else { return false }
        return Int(suffix) != nil
    }

    /// The trailing element of a section header. A Combined module's pill is a
    /// long segmented run (every metric + its bars) that would overflow the
    /// panel width here — and its members are already itemised as rows below —
    /// so a combined section shows just a compact overall-status dot instead of
    /// the full pill. Every other module shows its normal (short) header pill.
    @ViewBuilder
    private func headerTrailing(for item: PanelItem) -> some View {
        if item.content.face.segments != nil {
            Circle()
                .fill(tintColor(item.content.face.tint))
                .frame(width: 8, height: 8)
                .help(item.content.face.tooltip ?? "")
        } else {
            PillView(headerPill(for: item))
        }
    }

    /// The header pill with any leading token that duplicates the section title
    /// stripped (see `PanelDedup`). Combined pills (segmented) are left as-is.
    private func headerPill(for item: PanelItem) -> PillContent {
        let face = item.content.face
        guard face.segments == nil else { return item.content }
        let text = PanelDedup.headerPillText(title: item.title, pillText: face.text)
        guard text != face.text else { return item.content }
        let newFace = PillFace(text: text, symbolName: face.symbolName, tint: face.tint,
                               tooltip: face.tooltip, segments: nil, badge: face.badge)
        return PillContent(face: newFace, freshness: item.content.freshness, asOf: item.content.asOf)
    }

    /// A row is a redundant summary when it isn't interactive (no link, action or
    /// remove button) and its title only restates the header.
    private func isRedundantSummary(_ row: DetailRow, item: PanelItem) -> Bool {
        guard row.url == nil, row.action == nil, row.secondaryAction == nil else { return false }
        return PanelDedup.titleIsRedundant(rowTitle: row.title, headerTitle: item.title,
                                           pillText: item.content.face.text)
    }

    /// What's left of a redundant summary row once its repeated title is dropped:
    /// the graph and a subtitle the pill doesn't already show. Renders nothing
    /// when there's no new information (the row vanishes entirely).
    @ViewBuilder
    private func summaryStrip(_ row: DetailRow, pillText: String) -> some View {
        let subtitle = PanelDedup.novelSubtitle(row.subtitle, pillText: pillText)
        let hasSparkline = (row.sparkline?.count ?? 0) > 1
        let hasProgress = row.progress != nil
        if subtitle != nil || hasSparkline || hasProgress {
            HStack(spacing: 9) {
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(palette.ink(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let points = row.sparkline, points.count > 1 {
                    Sparkline(points: points, color: tintColor(row.tint))
                        .frame(width: 64, height: 18)
                }
                if let progress = row.progress {
                    MiniBar(value: progress, color: tintColor(row.tint))
                        .frame(width: 56, height: 5)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func detailRow(_ row: DetailRow) -> some View {
        let content = HStack(spacing: 9) {
            if let symbol = row.symbolName {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(tintColor(row.tint))
                    .frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 1) {
                ScrollableLine {
                    Text(row.title)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.ink(0.9))
                }
                if let subtitle = row.subtitle {
                    ScrollableLine {
                        Text(subtitle)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(palette.ink(0.5))
                    }
                }
            }
            Spacer(minLength: 8)
            if let points = row.sparkline, points.count > 1 {
                Sparkline(points: points, color: tintColor(row.tint))
                    .frame(width: 64, height: 18)
            }
            if let progress = row.progress {
                MiniBar(value: progress, color: tintColor(row.tint))
                    .frame(width: 56, height: 5)
            }
            if row.url != nil {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())

        // The row's primary tap (open / action / url), then an optional trailing
        // remove button as a *sibling* — never a button nested in a button.
        HStack(spacing: 0) {
            if let action = row.action {
                Button { actions.onAction(action) } label: { content }.buttonStyle(.plain)
            } else if let urlString = row.url, let url = URL(string: urlString) {
                Button { NSWorkspace.shared.open(url) } label: { content }.buttonStyle(.plain)
            } else {
                content
            }
            if let secondary = row.secondaryAction {
                Button { actions.onAction(secondary) } label: {
                    Image(systemName: row.secondaryIcon ?? "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.ink(0.35))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .help("Remove")
            }
        }
    }

    private func tintColor(_ tint: Tint) -> Color { palette.color(for: tint) }

    private var footer: some View {
        HStack(spacing: 8) {
            if !isConnected {
                controlButton("Connect GitHub", system: "person.badge.key", tint: palette.accent, action: actions.onConnect)
            }
            controlButton("Settings", system: "gearshape", action: actions.onSettings)
            controlButton("Reload", system: "arrow.clockwise", action: actions.onReload)
            Spacer(minLength: 0)
            controlButton("Quit", system: "power", action: actions.onQuit)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func controlButton(_ title: String, system: String, tint: Color? = nil,
                               action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: system)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle((tint ?? palette.onSurface).opacity(0.9))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(palette.ink(0.08)))
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    /// Apply `transform` only when `condition`, so auto-surfaced rows stay free
    /// of drag/drop modifiers while the reorder call sites remain readable.
    @ViewBuilder func ifReorderable(_ condition: Bool,
                                    _ transform: (Self) -> some View) -> some View {
        if condition { transform(self) } else { self }
    }
}

/// A single line of content the user can SWIPE sideways to read in full when it's
/// too long — instead of it being cut off with an ellipsis. No animation: it only
/// moves when the user scrolls it (two-finger swipe). Short content that already
/// fits just doesn't scroll. Vertical swipes pass through to the panel's own
/// scroll, and a click still activates the enclosing row (scroll ≠ tap).
struct ScrollableLine<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)   // never truncate; overflow scrolls
        }
        // Don't let the horizontal scroll steal vertical drags from the panel.
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}
