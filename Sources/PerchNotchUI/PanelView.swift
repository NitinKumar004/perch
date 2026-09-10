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
    @State private var edgeScrollTask: Task<Void, Never>?   // auto-scroll while dragging near an edge
    @State private var edgeDir: Int = 0                      // -1 up / +1 down / 0 idle (current auto-scroll)
    // Section/viewport frames live in a plain reference box, mutated in place, so
    // the per-frame geometry updates during a reorder DON'T invalidate the view
    // (writing to @State here would re-render the whole panel 60×/sec = the hang).
    @State private var geom = ReorderGeometry()
    @State private var scrollProxy: ScrollViewProxy?         // to drive auto-scroll during a drag
    @State private var expanded: Set<String> = []  // sections showing their full list
    @State private var copiedRowID: String?        // row whose link was just copied (brief ✓)
    @State private var openInfoID: String?         // tile whose ⓘ explanation is open
    @Environment(\.palette) private var palette
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // Rows scroll if they exceed the panel height, so a rich panel (many
            // modules / a long PR list) never gets clipped.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        rows
                    }
                }
                .frame(maxHeight: 300)
                // Track the viewport's on-screen frame + keep the proxy, so a drag
                // near an edge can auto-scroll the list itself.
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { scrollProxy = proxy; geom.viewport = g.frame(in: .global) }
                        .onChange(of: g.frame(in: .global)) { _, f in geom.viewport = f }
                })
                // Each section reports its on-screen frame; the drag hit-tests the
                // cursor against these to know which section it's over. Stored in the
                // plain box so this high-frequency update costs no re-render.
                .onPreferenceChange(SectionFramesKey.self) { geom.sections = $0 }
            }

            footer
        }
        .padding(.vertical, 4)
        .frame(width: 380)
        .background(cardSurface)
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        // A soft accent halo only for the "glow" material — the theme's premium
        // signature; zero-radius (invisible) otherwise, so it costs nothing.
        .shadow(color: theme.material == .glow ? palette.accent.opacity(0.45) : .clear,
                radius: theme.material == .glow ? 26 : 0, y: 6)
        // Pause an auto-open's auto-close countdown while the pointer is over the
        // panel (you're reading it), resume it when the pointer leaves.
        .onHover { actions.onHover($0) }
        // Drop files anywhere on the panel → the file shelf (if configured).
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            loadDroppedURLs(providers)
            return true
        }
        .coordinateSpace(name: "panel")
        .onAppear { order = items.map(\.id) }
        .onChange(of: items.map(\.id)) { _, ids in
            // Adopt an external order change (config reload) when not mid-drag.
            if draggingID == nil { order = ids }
        }
        // If the panel is dismissed mid-drag with the cursor near an edge, the
        // edge-auto-scroll loop is otherwise never cancelled — tear it down here.
        .onDisappear { edgeScrollTask?.cancel() }
    }

    /// The panel's card surface, themed. "Frosted" blurs what's behind (macOS
    /// vibrancy) under a translucent tint; otherwise a flat fill. The corner shape
    /// follows the theme's `radius`, in one place.
    private var cardSurface: some View {
        let r = theme.radius(18)
        return theme.materialFill(radius: r)
            .overlay(RoundedRectangle(cornerRadius: r, style: .continuous)
                .strokeBorder(isDropTargeted ? palette.accent : palette.ink(0.08),
                              lineWidth: isDropTargeted ? 2 : 1))
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

    /// Slide the dragged row to the slot the cursor is over — computed as an
    /// ABSOLUTE index (how many OTHER rows sit, by their midpoint, above the
    /// cursor) rather than relative to a target row. Absolute placement is
    /// idempotent, so the row reaches the very top (index 0) and never flip-flops
    /// between two slots as it passes a neighbour.
    private func moveDragged(_ moving: String, toCursorY y: CGFloat) {
        let current = order.isEmpty ? items.map(\.id) : order
        let index = current.filter { $0 != moving && (geom.sections[$0]?.midY ?? .infinity) < y }.count
        let next = PanelReorder.moved(current, moving: moving, toIndex: index)
        guard next != current else { return }
        // A snappy interactive spring so the other sections glide open a gap without
        // overshoot or lingering — the "auto-adjust" the reorder is meant to feel.
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.86)) { order = next }
    }

    /// Persist whatever order the live drag settled on.
    private func commitReorder() {
        setEdgeScroll(0)
        guard draggingID != nil else { return }
        draggingID = nil
        actions.onReorder(order.isEmpty ? items.map(\.id) : order)
    }

    /// Driven continuously by the header DragGesture (global cursor point): pick the
    /// section under the cursor and slide the dragged one into its place, and turn
    /// edge auto-scroll on/off when the cursor nears the viewport's top/bottom.
    private func handleReorderDrag(_ id: String, at point: CGPoint) {
        if draggingID != id { draggingID = id }

        // Move to the absolute slot under the cursor (idempotent — reaches the top,
        // never flip-flops). Replaces the old "reorder only when squarely inside a
        // target band" rule, which couldn't target above the first row and oscillated
        // once the dragged row reached the top.
        moveDragged(id, toCursorY: point.y)

        // Auto-scroll when the cursor is within `margin` of an edge (works BOTH ways).
        let vp = geom.viewport
        let margin: CGFloat = 34
        if vp.height > 0, point.y < vp.minY + margin { setEdgeScroll(-1) }
        else if vp.height > 0, point.y > vp.maxY - margin { setEdgeScroll(1) }
        else { setEdgeScroll(0) }
    }

    /// End of a header drag: stop scrolling and persist the order.
    private func endReorderDrag() { commitReorder() }

    /// Start/stop the auto-scroll loop for a direction (-1 up, +1 down, 0 stop).
    /// Idempotent per direction so continued cursor movement doesn't restart it.
    private func setEdgeScroll(_ dir: Int) {
        guard dir != edgeDir else { return }
        edgeDir = dir
        edgeScrollTask?.cancel()
        guard dir != 0, let proxy = scrollProxy else { edgeScrollTask = nil; return }
        edgeScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                // Find the next section just outside the viewport in `dir` and bring
                // it into view; live frames make this self-correcting each beat.
                let vp = geom.viewport
                if dir > 0 {
                    if let below = orderedItems.first(where: { (geom.sections[$0.id]?.maxY ?? -.infinity) > vp.maxY - 4 }) {
                        withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(below.id, anchor: .bottom) }
                    }
                } else {
                    if let above = orderedItems.last(where: { (geom.sections[$0.id]?.minY ?? .infinity) < vp.minY + 4 }) {
                        withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(above.id, anchor: .top) }
                    }
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
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
                    .font(theme.font(11))
                    .foregroundStyle(palette.ink(0.4))
                    .padding(.vertical, 14)
            }
        }
    }

    /// One module's section (header + its detail rows). Reorderable sections can
    /// be dragged by their header; as a drag passes over other sections they
    /// slide to open a gap, and the dragged one is highlighted (not faded) until
    /// it's dropped.
    @ViewBuilder
    private func section(_ item: PanelItem) -> some View {
        let reorderable = isReorderable(item)
        let isDragging = draggingID == item.id
        VStack(spacing: 0) {
            // Header: module name (+ what it watches) and its pill.
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(theme.font(12, .semibold))
                        .foregroundStyle(palette.ink(0.85))
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(theme.font(10))
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
            // The header is the drag handle — a real DragGesture (not SwiftUI
            // drag-and-drop) so we fully control live reorder + edge auto-scroll,
            // and it never fights the ScrollView (which scrolls by wheel, not drag)
            // or the tappable links/buttons in the detail rows below.
            .ifReorderable(reorderable) { $0.gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { v in handleReorderDrag(item.id, at: v.location) }
                    .onEnded { _ in endReorderDrag() }
            ) }

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
                metricGrid(Array(item.detail.prefix(shown)))
            } else {
                // Group the rows: full-width rows (hero chart, PRs, …) render one
                // per line; a run of `compact` stat tiles (per-model split, usage
                // insights) renders two-per-line in the grid, staying dense.
                ForEach(rowGroups(Array(item.detail.prefix(shown)))) { group in
                    switch group {
                    case .flow(let row):
                        if row.bars != nil {
                            chartRow(row)   // a hero chart is never collapsed
                        } else if isRedundantSummary(row, item: item) {
                            summaryStrip(row, pillText: item.content.face.text)
                        } else {
                            detailRow(row)
                        }
                    case .grid(let rows):
                        metricGrid(rows)
                    }
                }
            }
            if PanelCollapse.isCollapsible(total: item.detail.count) {
                expandToggle(id: item.id, total: item.detail.count, expanded: isExpanded)
            }
        }
        // The section being moved stays FULLY readable — no wash-out. A soft accent
        // tint + outline marks it as the one you're dragging, so it reads like its
        // normal self sitting in a highlighted slot, not a faded ghost.
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.accent.opacity(isDragging ? 0.12 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.accent.opacity(isDragging ? 0.45 : 0), lineWidth: 1)
        )
        // A gentle lift while held — slightly scaled and shadowed, raised above its
        // neighbours so it reads as "picked up".
        .scaleEffect(isDragging ? 1.02 : 1, anchor: .center)
        .shadow(color: .black.opacity(isDragging ? 0.35 : 0), radius: isDragging ? 10 : 0, y: isDragging ? 4 : 0)
        .zIndex(isDragging ? 1 : 0)
        .animation(.easeOut(duration: 0.16), value: isDragging)
        // Report this section's on-screen frame so the drag can hit-test the cursor
        // against it (which section am I over?) and drive auto-scroll.
        .background(GeometryReader { g in
            Color.clear.preference(key: SectionFramesKey.self, value: [item.id: g.frame(in: .global)])
        })
    }

    /// A group of a section's rows for layout: either a full-width row, or a run
    /// of compact stat tiles that pack two-per-line.
    private enum RowGroup: Identifiable {
        case flow(DetailRow)
        case grid([DetailRow])
        var id: String {
            switch self {
            case .flow(let r): return "flow-\(r.id)"
            case .grid(let rs): return "grid-\(rs.first?.id ?? "")"
            }
        }
    }

    /// Partition rows into full-width singles and runs of compact tiles, preserving
    /// order — so consecutive `compact` rows collapse into one grid while anything
    /// full-width (a hero chart, a PR) stays on its own line.
    private func rowGroups(_ rows: [DetailRow]) -> [RowGroup] {
        var groups: [RowGroup] = []
        var bucket: [DetailRow] = []
        func flush() {
            if !bucket.isEmpty { groups.append(.grid(bucket)); bucket = [] }
        }
        for row in rows {
            if row.compact && row.bars == nil {
                bucket.append(row)
            } else {
                flush()
                groups.append(.flow(row))
            }
        }
        flush()
        return groups
    }

    /// A run of stat tiles, two per line, each as its own little block: icon +
    /// name, the value, and — for a trending/percentage metric — its trend graph
    /// or level bar. Used by the Combined section and by any run of `compact`
    /// rows (per-model split, usage insights). The panel scrolls when there are
    /// more than fit.
    @ViewBuilder
    private func metricGrid(_ rows: [DetailRow]) -> some View {
        // FIXED column width, not flexible: two 166pt columns + 8pt gap + 28pt
        // padding = 368pt < the 380pt card. Fixed columns can never expand to make
        // the panel overflow — flexible ones did, and no outer frame could shrink
        // them back below their content's minimum, so the labels got sliced off.
        VStack(spacing: 8) {
            LazyVGrid(
                columns: [GridItem(.fixed(166), spacing: 8, alignment: .top),
                          GridItem(.fixed(166), spacing: 8, alignment: .top)],
                alignment: .leading, spacing: 8
            ) {
                ForEach(rows) { row in metricBlock(row) }
            }
            // The tapped tile's explanation, inline under this grid group.
            if let id = openInfoID, let row = rows.first(where: { $0.id == id }), row.info != nil {
                infoCard(row)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    /// A fixed tile height so every stat block in the grid is the same size,
    /// regardless of whether it has a graph or a longer value.
    private let metricTileHeight: CGFloat = 56

    /// One metric block: name on top, then the value and its graph. Single-line
    /// value (shrinks a touch rather than wrapping) so all tiles are one uniform
    /// height. An ⓘ hint appears when the row carries an explanation.
    private func metricBlock(_ row: DetailRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if let symbol = row.symbolName {
                    Image(systemName: symbol)
                        .font(theme.font(11))
                        .foregroundStyle(tintColor(row.tint))
                }
                Text(row.title)
                    .font(theme.font(11, .semibold))
                    .foregroundStyle(palette.ink(0.9))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let info = row.info, !info.isEmpty {
                    let isOpen = openInfoID == row.id
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            openInfoID = isOpen ? nil : row.id
                        }
                    } label: {
                        Image(systemName: isOpen ? "info.circle.fill" : "info.circle")
                            .font(theme.font(11))
                            .foregroundStyle(isOpen ? tintColor(row.tint) : palette.ink(0.4))
                    }
                    .buttonStyle(.plain)
                    .help(info)
                }
            }
            HStack(alignment: .bottom, spacing: 6) {
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(theme.font(11))
                        .foregroundStyle(palette.ink(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)            // shrink a hair, never wrap
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
            Spacer(minLength: 0)   // pin content to the top so short tiles match tall ones
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: metricTileHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.ink(0.05))
        )
    }

    /// The explanation card shown under a tile grid when a tile's ⓘ is tapped —
    /// full-width so a long, plain-language "what this means / why it matters"
    /// reads cleanly. Tapping ⓘ again closes it.
    private func infoCard(_ row: DetailRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: row.symbolName ?? "info.circle")
                .font(theme.font(11))
                .foregroundStyle(tintColor(row.tint))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(theme.font(11, .semibold))
                    .foregroundStyle(palette.ink(0.9))
                Text(row.info ?? "")
                    .font(theme.font(10))
                    .foregroundStyle(palette.ink(0.65))
                    .fixedSize(horizontal: false, vertical: true)   // wrap, full text
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.accent.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(palette.accent.opacity(0.25)))
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
                    .font(theme.font(9, .bold))
                Text(expanded ? "Show less" : "Show all \(total)")
                    .font(theme.font(11, .medium))
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
                        .font(theme.font(10))
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

    /// A "hero" chart row: the value as a bold headline, a full-width bar chart,
    /// and a caption below — so a daily series (tokens/day) fills the row's width
    /// instead of squeezing a chart against the right edge with dead space beside
    /// it. Used whenever a row carries `bars`.
    @ViewBuilder
    private func chartRow(_ row: DetailRow) -> some View {
        let labels = row.barLabels ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let symbol = row.symbolName {
                    Image(systemName: symbol)
                        .font(theme.font(13))
                        .foregroundStyle(tintColor(row.tint))
                }
                Text(row.title)
                    .font(theme.font(16, .semibold))
                    .foregroundStyle(palette.ink(0.92))
                Spacer(minLength: 0)
            }
            if let bars = row.bars, bars.count > 1 {
                VStack(spacing: 4) {
                    BarChart(points: bars, color: tintColor(row.tint), labels: labels)
                        .frame(height: 46)
                    // Oldest → newest axis, so the timeline direction is explicit
                    // and each end is dated (hover a bar for its exact day).
                    if let first = labels.first, let last = labels.last, first != last {
                        HStack {
                            Text(first)
                            Spacer(minLength: 8)
                            Text(last)
                        }
                        .font(theme.font(9))
                        .foregroundStyle(palette.ink(0.4))
                    }
                }
            }
            if let subtitle = row.subtitle {
                Text(subtitle)
                    .font(theme.font(10))
                    .foregroundStyle(palette.ink(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func detailRow(_ row: DetailRow) -> some View {
        let content = HStack(spacing: 9) {
            if let symbol = row.symbolName {
                Image(systemName: symbol)
                    .font(theme.font(11))
                    .foregroundStyle(tintColor(row.tint))
                    .frame(width: 16)
            }
            // Title + subtitle you can SLIDE by hand to read anything cut off at the
            // edge — both lines share one offset so they move together. Width-safe:
            // a long title can't widen the panel. Click still opens the row.
            ManualSlide(title: row.title, titleFont: theme.font(12), titleColor: palette.ink(0.9),
                        subtitle: row.subtitle, subFont: theme.font(10), subColor: palette.ink(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(row.subtitle.map { "\(row.title) · \($0)" } ?? row.title)
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
                    .font(theme.font(11))
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
            // Copy the row's link (a PR, a notification, a build) so it can be
            // shared without opening it. A brief checkmark confirms the copy.
            if let urlString = row.url {
                let copied = copiedRowID == row.id
                Button { copyLink(urlString, rowID: row.id) } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(theme.font(11))
                        .foregroundStyle(copied ? palette.good : palette.ink(0.4))
                }
                .buttonStyle(.plain)
                .padding(.trailing, row.secondaryAction == nil ? 12 : 6)
                .help(copied ? "Copied!" : "Copy link")
            }
            if let secondary = row.secondaryAction {
                Button { actions.onAction(secondary) } label: {
                    Image(systemName: row.secondaryIcon ?? "xmark.circle.fill")
                        .font(theme.font(12))
                        .foregroundStyle(palette.ink(0.35))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .help("Remove")
            }
        }
    }

    /// Copy a row's link to the clipboard and show a short-lived checkmark on that
    /// row. Re-copying a different row moves the checkmark; the confirmation
    /// clears itself after a moment.
    private func copyLink(_ urlString: String, rowID: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { copiedRowID = rowID }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if copiedRowID == rowID { withAnimation(.easeOut(duration: 0.2)) { copiedRowID = nil } }
        }
    }

    private func tintColor(_ tint: Tint) -> Color { palette.color(for: tint) }

    private var footer: some View {
        HStack(spacing: 8) {
            // GitHub is the only connection-requiring integration today, so the
            // affordance names it directly. A second provider would generalize
            // this to the `ModuleDescriptor.requiresConnection` contract (already
            // used in Settings) + a provider abstraction — deferred until one
            // exists, rather than building speculative machinery for one provider.
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
                .font(theme.font(11, .medium))
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

/// A plain reference box for the drag's geometry (section frames + viewport). It's
/// mutated in place during a drag so the high-frequency updates never invalidate
/// the SwiftUI view — writing these into @State re-rendered the whole panel every
/// animation frame, which is what made dragging hang.
private final class ReorderGeometry {
    var sections: [String: CGRect] = [:]
    var viewport: CGRect = .zero
}

/// Collects each reorderable section's on-screen frame (keyed by id) so a header
/// drag can hit-test the cursor against them and drive auto-scroll.
private struct SectionFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

