import Foundation
import PerchCore
import PerchModuleKit

// MARK: - Wire shape (Claude Code's ~/.claude/stats-cache.json)

/// The locally-cached activity Claude Code writes to `~/.claude/stats-cache.json`.
/// Lenient — every field optional so a schema change across CLI versions degrades
/// to "less data", never a crash.
struct AIUsageStats: Decodable {
    let dailyActivity: [DayActivity]?
    let dailyModelTokens: [DayModelTokens]?
    let modelUsage: [String: ModelUsage]?
    let hourCounts: [String: Int]?
    let totalSessions: Int?
    let totalMessages: Int?
    let firstSessionDate: String?

    struct DayActivity: Decodable {
        let date: String
        let messageCount: Int?
        let sessionCount: Int?
        let toolCallCount: Int?
    }
    struct DayModelTokens: Decodable {
        let date: String
        let tokensByModel: [String: Int]
    }
    /// Per-model token accounting — the split between fresh input, generated
    /// output, and (the big one) cached context that's re-sent each turn.
    struct ModelUsage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?
    }
}

// MARK: - Normalized snapshot (what the pill + panel render)

public struct AIDayPoint: Sendable, Equatable {
    public let date: String
    public let tokens: Int
    public init(date: String, tokens: Int) { self.date = date; self.tokens = tokens }
}
public struct AIModelBreak: Sendable, Equatable {
    public let model: String
    public let tokens: Int
    public init(model: String, tokens: Int) { self.model = model; self.tokens = tokens }
}

/// Everything the AI-usage view needs, normalized so any agent's reader can
/// produce it (Claude today; Cursor/others later behind the same shape).
public struct AIUsageSnapshot: Sendable, Equatable {
    public var windowTokens: Int         // total over the last N days (the headline)
    public var windowMessages: Int
    public var latestDate: String?       // the most recent day WITH data (freshness-honest)
    public var latestTokens: Int
    public var series: [AIDayPoint]      // last N days, oldest → newest (the graph)
    public var byModel: [AIModelBreak]   // the latest day's split, biggest first
    public var totalSessions: Int
    public var totalMessages: Int
    public var sinceDate: String?

    // Insights — things Claude's own stats don't surface directly, all computed
    // exactly from the local data.
    /// Share (0…1) of all input tokens that were CACHED context re-sent each turn
    /// (vs fresh input) — the "context reuse" signal, and the biggest cost lever.
    public var cacheReuse: Double?
    /// Busiest hour of the day (0…23) across all activity, or nil if unknown.
    public var peakHour: Int?
    /// The single biggest day ever by tokens (all-time, not just the window).
    public var busiestDate: String?
    public var busiestTokens: Int
    /// Lifetime tool calls run (real automation volume).
    public var toolCalls: Int

    public init(windowTokens: Int = 0, windowMessages: Int = 0,
                latestDate: String? = nil, latestTokens: Int = 0,
                series: [AIDayPoint] = [], byModel: [AIModelBreak] = [],
                totalSessions: Int = 0, totalMessages: Int = 0, sinceDate: String? = nil,
                cacheReuse: Double? = nil, peakHour: Int? = nil,
                busiestDate: String? = nil, busiestTokens: Int = 0, toolCalls: Int = 0) {
        self.windowTokens = windowTokens; self.windowMessages = windowMessages
        self.latestDate = latestDate; self.latestTokens = latestTokens
        self.series = series; self.byModel = byModel
        self.totalSessions = totalSessions; self.totalMessages = totalMessages; self.sinceDate = sinceDate
        self.cacheReuse = cacheReuse; self.peakHour = peakHour
        self.busiestDate = busiestDate; self.busiestTokens = busiestTokens; self.toolCalls = toolCalls
    }
    public static let empty = AIUsageSnapshot()
}

// MARK: - Reader (pure, tested)

/// Turns the raw stats into the normalized snapshot. Pure over data, so it's
/// fully unit-testable with fixtures — no files, no clock.
public enum AIUsageReader {
    /// A rolling window over the last `days` of data — robust to the stats file
    /// being computed lazily (so "today" may lag).
    static func snapshot(from s: AIUsageStats, days: Int) -> AIUsageSnapshot {
        let daily = s.dailyModelTokens ?? []
        let window = Array(daily.suffix(max(1, days)))
        let series = window.map { AIDayPoint(date: $0.date, tokens: $0.tokensByModel.values.reduce(0, +)) }
        let windowDates = Set(series.map(\.date))
        // The latest day WITH data drives the per-model split (freshness-honest).
        let latest = window.last
        let byModel = (latest?.tokensByModel ?? [:])
            .map { AIModelBreak(model: $0.key, tokens: $0.value) }
            .sorted { $0.tokens > $1.tokens }
        let windowMessages = (s.dailyActivity ?? [])
            .filter { windowDates.contains($0.date) }
            .reduce(0) { $0 + ($1.messageCount ?? 0) }

        // --- Insights (exact, from the whole dataset — not just the window) ---
        // Context reuse: cached input re-sent each turn ÷ all input-side tokens.
        let mu = s.modelUsage?.values
        let cacheRead = mu?.reduce(0) { $0 + ($1.cacheReadInputTokens ?? 0) } ?? 0
        let cacheCreate = mu?.reduce(0) { $0 + ($1.cacheCreationInputTokens ?? 0) } ?? 0
        let freshInput = mu?.reduce(0) { $0 + ($1.inputTokens ?? 0) } ?? 0
        let inputSide = cacheRead + cacheCreate + freshInput
        let cacheReuse: Double? = inputSide > 0 ? Double(cacheRead) / Double(inputSide) : nil
        // Peak hour of day across all activity. Deterministic tie-break: on an
        // equal count the earlier hour wins (a Dictionary has no order, so without
        // this the "peak hour" could change between launches).
        let peakHour = (s.hourCounts ?? [:])
            .compactMap { key, count in Int(key).map { (hour: $0, count: count) } }
            .max { a, b in a.count != b.count ? a.count < b.count : a.hour > b.hour }
            .map(\.hour)
        // Biggest day ever by tokens (all-time).
        let busiest = daily.map { ($0.date, $0.tokensByModel.values.reduce(0, +)) }
            .max { a, b in a.1 < b.1 }
        // Lifetime tool calls.
        let toolCalls = (s.dailyActivity ?? []).reduce(0) { $0 + ($1.toolCallCount ?? 0) }

        return AIUsageSnapshot(
            windowTokens: series.reduce(0) { $0 + $1.tokens },
            windowMessages: windowMessages,
            latestDate: latest?.date,
            latestTokens: series.last?.tokens ?? 0,
            series: series,
            byModel: byModel,
            totalSessions: s.totalSessions ?? 0,
            totalMessages: s.totalMessages ?? 0,
            sinceDate: s.firstSessionDate,
            cacheReuse: cacheReuse,
            peakHour: peakHour,
            busiestDate: busiest?.0,
            busiestTokens: busiest?.1 ?? 0,
            toolCalls: toolCalls)
    }

    /// A 24h hour index → a friendly 12h label. 0 → "12 AM", 11 → "11 AM",
    /// 17 → "5 PM". Out-of-range falls back to the raw number.
    public static func hourLabel(_ h: Int) -> String {
        guard (0...23).contains(h) else { return "\(h):00" }
        let period = h < 12 ? "AM" : "PM"
        let twelve = h % 12 == 0 ? 12 : h % 12
        return "\(twelve) \(period)"
    }

    /// "2026-09-08" → "Sep 8" — a short, human day label for the chart axis and
    /// per-bar tooltips. Falls back to the raw string's date part if unparseable.
    public static func shortDay(_ iso: String) -> String {
        let key = String(iso.prefix(10))
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: key) else { return key }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US")
        out.timeZone = .current
        out.dateFormat = "MMM d"
        return out.string(from: date)
    }

    /// "claude-opus-4-8" → "Opus 4.8".
    public static func prettyModel(_ id: String) -> String {
        var s = id
        if s.hasPrefix("claude-") { s = String(s.dropFirst("claude-".count)) }
        let parts = s.split(separator: "-").map(String.init)
        guard let family = parts.first else { return id }
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? family.capitalized : "\(family.capitalized) \(version)"
    }
}

// MARK: - Module

/// Reads a coding agent's LOCAL activity file and shows your token usage — a
/// glanceable "AI 3.5B today" pill and a panel with a daily-trend graph, per-model
/// breakdown, and lifetime totals. Local-first: no login, no API key. Claude Code
/// today (`~/.claude/stats-cache.json`); other agents plug in behind the same
/// snapshot shape.
public struct AIUsageModule: NotchModule {
    public typealias State = AIUsageSnapshot

    public static let descriptor = ModuleDescriptor(
        id: "ai.usage",
        name: "AI Usage",
        summary: "Your local AI-agent token usage + daily trend.",
        supportedSlots: [.leftPill, .panel],
        requiresConnection: false,
        detailFirst: true          // the daily chart + insights ARE the feature — surface the panel when pilled
    )

    private let dir: String
    private let metric: String   // "tokens" | "messages"
    private let days: Int
    private let insights: Bool   // show the derived-insight rows (cache reuse, peak hour, …)

    public init(dir: String = "~/.claude", metric: String = "tokens", days: Int = 14,
                insights: Bool = true) {
        self.dir = dir
        self.metric = metric
        self.days = max(5, min(60, days))
        self.insights = insights
    }

    private var fileURL: URL {
        URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
            .appendingPathComponent("stats-cache.json")
    }

    /// Distinguishes this instance's detail-row ids from another AIUsage instance
    /// configured with different settings, so a per-row control (the ⓘ) can't fire
    /// on an identically-labelled tile in the other instance's section.
    private var idScope: String { "\(dir)|\(metric)|\(days)|\(insights)" }
    private func rowID(_ key: String) -> String { "aiusage-\(idScope)-\(key)" }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<AIUsageSnapshot>> {
        let interval = context.refreshSeconds(fallback: 120, minimum: 30)
        let url = fileURL
        let days = days
        // Reuse the shared periodic sampler: it owns the Task lifecycle + teardown,
        // seeds an `.unknown` empty row before the first read, and — crucially here
        // — re-emits the last good value as `.stale` when a read fails, instead of
        // flashing to "no data" every time our poll races Claude Code rewriting the
        // stats file on the same cadence. Returning nil = "couldn't read this tick".
        return .periodic(every: interval, clock: context.clock, seed: .empty) {
            guard let data = try? Data(contentsOf: url),
                  let stats = try? JSONDecoder().decode(AIUsageStats.self, from: data) else {
                return nil
            }
            return AIUsageReader.snapshot(from: stats, days: days)
        }
    }

    public func face(for value: AIUsageSnapshot, in slot: Slot) -> PillFace {
        if metric == "messages" {
            return PillFace(text: "AI " + NumberFormat.compact(value.windowMessages),
                            symbolName: "sparkles", tint: .info,
                            tooltip: "\(value.windowMessages) messages · last \(days) days")
        }
        return PillFace(text: "AI " + NumberFormat.compact(value.windowTokens),
                        symbolName: "sparkles", tint: .info,
                        tooltip: "\(value.windowTokens) tokens · last \(days) days")
    }

    public func contextLabel(_ context: ModuleContext) -> String? {
        "Claude Code · last \(days) days"
    }

    public func detail(for value: AIUsageSnapshot) -> [DetailRow] {
        guard !value.series.isEmpty || value.totalMessages > 0 else { return [] }
        var rows: [DetailRow] = []
        // Hero: the window total as a headline over a full-width daily bar chart.
        // No leading icon (the headline carries it); the chart's axis + per-bar
        // hover tooltips carry the dates, so each bar is identifiable by day.
        rows.append(DetailRow(
            id: rowID("window"),
            title: "\(NumberFormat.compact(value.windowTokens)) tokens",
            subtitle: "last \(days) days · \(NumberFormat.compact(value.windowMessages)) messages",
            tint: .info, symbolName: nil,
            bars: value.series.map { Double($0.tokens) },
            barLabels: value.series.map { AIUsageReader.shortDay($0.date) }))
        // Per-model split for the latest day, as compact tiles (two per line) with
        // a share bar — the mix at a glance (Opus vs Sonnet …) without a long list.
        let latestTotal = value.byModel.reduce(0) { $0 + $1.tokens }
        for m in value.byModel.prefix(4) where m.tokens > 0 {
            rows.append(DetailRow(
                id: rowID(m.model),
                title: AIUsageReader.prettyModel(m.model),
                subtitle: NumberFormat.compact(m.tokens),
                tint: .info, symbolName: "cpu",
                compact: true,
                info: "Tokens from \(AIUsageReader.prettyModel(m.model)) on the latest day, and its share of that day's total. Heavier models (Opus) cost more per token than lighter ones (Haiku).",
                progress: latestTotal > 0 ? Double(m.tokens) / Double(latestTotal) : nil))
        }
        // Insights — the value Claude's own stats don't surface. All exact, laid
        // out as compact tiles so they stay dense (label on top, value below).
        if insights {
            if let reuse = value.cacheReuse {
                rows.append(DetailRow(
                    id: rowID("cache"),
                    title: "Context reuse",
                    subtitle: "\(Int((reuse * 100).rounded()))%",
                    tint: .info, symbolName: "arrow.triangle.2.circlepath",
                    compact: true,
                    info: "Share of your input that is cached conversation context re-sent every turn, rather than new text. A high number is normal in long sessions — it's cheap per token, but it grows as a chat gets longer. Start a fresh session (/clear) between unrelated tasks to keep it down.",
                    progress: reuse))
            }
            if let peak = value.peakHour {
                rows.append(DetailRow(
                    id: rowID("peak"),
                    title: "Peak hour",
                    subtitle: AIUsageReader.hourLabel(peak),
                    tint: .neutral, symbolName: "clock", compact: true,
                    info: "The hour of the day you use Claude the most, across all your sessions — your busiest working window."))
            }
            if let busiest = value.busiestDate, value.busiestTokens > 0 {
                rows.append(DetailRow(
                    id: rowID("busiest"),
                    title: "Busiest day",
                    subtitle: "\(AIUsageReader.shortDay(busiest)) · \(NumberFormat.compact(value.busiestTokens))",
                    tint: .neutral, symbolName: "flame", compact: true,
                    info: "Your single biggest day ever by tokens used — the date and how many."))
            }
            if value.toolCalls > 0 {
                rows.append(DetailRow(
                    id: rowID("tools"),
                    title: "Tool calls",
                    subtitle: NumberFormat.compact(value.toolCalls),
                    tint: .neutral, symbolName: "wrench.and.screwdriver", compact: true,
                    info: "Total actions Claude has run for you — file edits, searches, shell commands, and other tools. A measure of real work done, not just messages."))
            }
        }
        // Lifetime footer.
        if value.totalMessages > 0 {
            rows.append(DetailRow(
                id: rowID("total"),
                title: "\(value.totalSessions) sessions · \(NumberFormat.compact(value.totalMessages)) messages",
                subtitle: value.sinceDate.map { "since \($0.prefix(10))" },
                tint: .neutral, symbolName: "clock"))
        }
        return rows
    }
}
