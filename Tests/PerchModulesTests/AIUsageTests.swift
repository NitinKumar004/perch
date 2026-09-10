import Testing
import Foundation
@testable import PerchModules

@Suite struct AIUsageTests {
    /// A stats-cache.json fixture in the real shape.
    let fixture = """
    {
      "dailyActivity": [
        {"date":"2026-09-07","messageCount":100,"sessionCount":1,"toolCallCount":5},
        {"date":"2026-09-08","messageCount":200,"sessionCount":2,"toolCallCount":9}
      ],
      "dailyModelTokens": [
        {"date":"2026-09-06","tokensByModel":{"claude-opus-4-8":1000}},
        {"date":"2026-09-07","tokensByModel":{"claude-opus-4-8":2000,"claude-sonnet-5":500}},
        {"date":"2026-09-08","tokensByModel":{"claude-opus-4-8":3000,"claude-sonnet-5":1000}}
      ],
      "modelUsage": {
        "claude-opus-4-8": {"inputTokens":100,"outputTokens":400,"cacheReadInputTokens":8000,"cacheCreationInputTokens":1500},
        "claude-sonnet-5": {"inputTokens":900,"outputTokens":600,"cacheReadInputTokens":2000,"cacheCreationInputTokens":500}
      },
      "hourCounts": {"9":4,"11":11,"17":9,"23":5},
      "totalSessions":108,"totalMessages":328689,"firstSessionDate":"2026-02-12T18:47:17.971Z"
    }
    """

    func snapshot(days: Int = 14) throws -> AIUsageSnapshot {
        let stats = try JSONDecoder().decode(AIUsageStats.self, from: Data(fixture.utf8))
        return AIUsageReader.snapshot(from: stats, days: days)
    }

    @Test func computesWindowSeriesAndModels() throws {
        let s = try snapshot()
        #expect(s.windowTokens == 7500)         // 1000 + 2500 + 4000 over the window
        #expect(s.windowMessages == 300)        // 100 + 200 (days with activity in window)
        #expect(s.latestTokens == 4000)         // most recent day
        #expect(s.latestDate == "2026-09-08")
        #expect(s.series.map(\.tokens) == [1000, 2500, 4000])   // per-day totals, oldest→newest
        #expect(s.byModel.first?.model == "claude-opus-4-8")     // biggest first (latest day)
        #expect(s.byModel.map(\.tokens) == [3000, 1000])
        #expect(s.totalSessions == 108)
        #expect(s.totalMessages == 328689)
        #expect(s.sinceDate?.hasPrefix("2026-02-12") == true)
    }

    @Test func insightsAreComputedExactly() throws {
        let s = try snapshot()
        // cache reuse = cacheRead / (cacheRead + cacheCreate + input)
        //            = 10000 / (10000 + 2000 + 1000) = 0.7692…
        #expect(abs((s.cacheReuse ?? 0) - (10000.0 / 13000.0)) < 0.0001)
        #expect(s.peakHour == 11)                    // busiest hour bucket
        #expect(s.busiestDate == "2026-09-08")       // biggest day all-time
        #expect(s.busiestTokens == 4000)
        #expect(s.toolCalls == 14)                   // 5 + 9
    }

    @Test func insightRowsRenderWhenEnabledAndHideWhenOff() throws {
        let snap = try snapshot()
        let on = AIUsageModule(insights: true).detail(for: snap)
        #expect(on.contains { $0.id.hasSuffix("-cache") && $0.progress != nil })
        #expect(on.contains { $0.title.contains("Peak hour") })
        #expect(on.contains { $0.title.contains("Busiest day") })
        // Insight + per-model rows are compact tiles (grid), the hero is not.
        #expect(on.first?.compact == false)                              // hero chart row
        let tiles = on.filter { !$0.id.hasSuffix("-window") && !$0.id.hasSuffix("-total") }
        let allTilesCompact = tiles.allSatisfy(\.compact)
        #expect(allTilesCompact)
        // Each insight tile carries an explanation (the ⓘ hint).
        let allTilesExplained = tiles.allSatisfy { $0.info?.isEmpty == false }
        #expect(allTilesExplained)
        let off = AIUsageModule(insights: false).detail(for: snap)
        #expect(!off.contains { $0.id.hasSuffix("-cache") || $0.id.hasSuffix("-peak") })
    }

    /// Two instances configured differently must not share row ids, or a per-row
    /// control (the ⓘ) fires on both instances' identically-labelled tiles.
    @Test func rowIDsAreUniquePerInstance() throws {
        let snap = try snapshot()
        let a = Set(AIUsageModule(dir: "~/.claude").detail(for: snap).map(\.id))
        let b = Set(AIUsageModule(dir: "~/.codex").detail(for: snap).map(\.id))
        #expect(!a.isEmpty && a.isDisjoint(with: b))
    }

    @Test func facePicksTheConfiguredMetric() throws {
        let snap = try snapshot()   // windowTokens 7500, windowMessages 300
        #expect(AIUsageModule(metric: "tokens").face(for: snap, in: .leftPill).text == "AI 7.5K")
        #expect(AIUsageModule(metric: "messages").face(for: snap, in: .leftPill).text == "AI 300")
    }

    @Test func peakHourTieBreaksToEarlierHour() throws {
        let json = #"{"hourCounts":{"14":5,"9":5}}"#
        let stats = try JSONDecoder().decode(AIUsageStats.self, from: Data(json.utf8))
        #expect(AIUsageReader.snapshot(from: stats, days: 14).peakHour == 9)
    }

    @Test func hourLabelsAreFriendly() {
        #expect(AIUsageReader.hourLabel(0) == "12 AM")
        #expect(AIUsageReader.hourLabel(11) == "11 AM")
        #expect(AIUsageReader.hourLabel(12) == "12 PM")
        #expect(AIUsageReader.hourLabel(17) == "5 PM")
        #expect(AIUsageReader.hourLabel(23) == "11 PM")
    }

    @Test func seriesHonorsTheDayWindow() throws {
        #expect(try snapshot(days: 5).series.count == 3)   // fewer days available → all of them
        #expect(try snapshot(days: 2).series.map(\.tokens) == [2500, 4000])   // last 2
        #expect(try snapshot(days: 2).windowTokens == 6500)   // only the last 2 days summed
    }

    @Test func emptyStatsIsZeroNotACrash() throws {
        let stats = try JSONDecoder().decode(AIUsageStats.self, from: Data("{}".utf8))
        let s = AIUsageReader.snapshot(from: stats, days: 14)
        #expect(s.windowTokens == 0)
        #expect(s.byModel.isEmpty)
        #expect(s.series.isEmpty)
    }

    @Test func prettyModelNames() {
        #expect(AIUsageReader.prettyModel("claude-opus-4-8") == "Opus 4.8")
        #expect(AIUsageReader.prettyModel("claude-sonnet-5") == "Sonnet 5")
        #expect(AIUsageReader.prettyModel("gpt-4o") == "Gpt 4o")
    }

    @Test func shortDayLabels() {
        #expect(AIUsageReader.shortDay("2026-09-08") == "Sep 8")
        #expect(AIUsageReader.shortDay("2026-01-15") == "Jan 15")
        #expect(AIUsageReader.shortDay("2026-09-08T00:00:00Z") == "Sep 8")   // trims time
        #expect(AIUsageReader.shortDay("not-a-date") == "not-a-date")        // graceful fallback
    }

    @Test func moduleDetailShowsTheGraphAndModels() {
        let m = AIUsageModule(dir: "~/.claude", metric: "tokens", days: 14)
        let snap = AIUsageSnapshot(windowTokens: 7500, windowMessages: 300,
                                   latestDate: "2026-09-08", latestTokens: 4000,
                                   series: [.init(date: "d1", tokens: 1000), .init(date: "d2", tokens: 4000)],
                                   byModel: [.init(model: "claude-opus-4-8", tokens: 3000)],
                                   totalSessions: 108, totalMessages: 328689, sinceDate: "2026-02-12")
        let rows = m.detail(for: snap)
        #expect(rows.first?.title.contains("tokens") == true)   // headline value
        #expect(rows.first?.subtitle?.contains("last 14 days") == true)
        #expect(rows.first?.symbolName == nil)                  // no leading icon on the hero
        #expect(rows.first?.bars == [1000, 4000])               // the hero bar chart
        #expect(rows.first?.barLabels == ["d1", "d2"])          // per-bar date labels (axis + hover)
        let opus = rows.first { $0.title == "Opus 4.8" }        // per-model row
        #expect(opus != nil)
        #expect(opus?.progress != nil)                          // with a share bar
        #expect(m.detail(for: .empty).isEmpty)                  // no data → no rows
    }
}
