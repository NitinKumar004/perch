import Testing
import Foundation
@testable import PerchCore

@Suite struct MetricThresholdsTests {
    @Test func standardLevelsColourByThreshold() {
        let t = MetricThresholds.standard   // cpu 70/90, mem 75/90, disk 85/95
        #expect(t.cpuTint(50) == .good)
        #expect(t.cpuTint(75) == .warning)
        #expect(t.cpuTint(95) == .critical)
        #expect(t.memoryTint(60) == .good)
        #expect(t.memoryTint(80) == .warning)
        #expect(t.diskTint(90) == .warning)
        #expect(t.diskTint(96) == .critical)
    }

    @Test func swapAndLoadUseTheirOwnUnits() {
        let t = MetricThresholds.standard   // swap 2/6 GB, load 0.9/1.5×
        let gb: UInt64 = 1_073_741_824
        #expect(t.swapTint(bytes: gb) == .good)          // 1 GB
        #expect(t.swapTint(bytes: 3 * gb) == .warning)   // 3 GB
        #expect(t.swapTint(bytes: 7 * gb) == .critical)  // 7 GB
        #expect(t.swapCriticalBytes == UInt64(6 * 1_073_741_824))
        #expect(t.loadTint(ratio: 0.5) == .good)
        #expect(t.loadTint(ratio: 1.0) == .warning)
        #expect(t.loadTint(ratio: 1.8) == .critical)
    }

    @Test func customLevelsRecolour() {
        // A user who sets a very tolerant swap level sees green where standard is red.
        var t = MetricThresholds.standard
        t.swapCriticalGB = 20
        t.swapWarnGB = 10
        #expect(t.swapTint(bytes: 7 * 1_073_741_824) == .good)   // 7 GB now fine
    }

    @Test func decodingIsTolerantOfMissingFields() throws {
        // An older config with only some fields set fills the rest from defaults.
        let json = Data(#"{"swapCriticalGB": 12}"#.utf8)
        let t = try JSONDecoder().decode(MetricThresholds.self, from: json)
        #expect(t.swapCriticalGB == 12)                  // the set field survives
        #expect(t.cpuWarn == MetricThresholds.standard.cpuWarn)   // the rest default
        #expect(t.loadCriticalRatio == MetricThresholds.standard.loadCriticalRatio)
    }

    @Test func roundTripsThroughCodable() throws {
        var t = MetricThresholds.standard
        t.cpuCritical = 85
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(MetricThresholds.self, from: data)
        #expect(back == t)
    }
}

@Suite struct AlertPacingTests {
    @Test func defaultsAreSensible() {
        #expect(AlertPacing.standard.dwellSeconds == 10)
        #expect(AlertPacing.standard.cooldownSeconds == 120)
    }

    @Test func decodingIsTolerantAndRoundTrips() throws {
        // Missing field falls back to default.
        let partial = try JSONDecoder().decode(AlertPacing.self, from: Data(#"{"dwellSeconds": 3}"#.utf8))
        #expect(partial.dwellSeconds == 3)
        #expect(partial.cooldownSeconds == AlertPacing.standard.cooldownSeconds)
        // Full round-trip.
        var p = AlertPacing.standard
        p.cooldownSeconds = 300
        let back = try JSONDecoder().decode(AlertPacing.self, from: JSONEncoder().encode(p))
        #expect(back == p)
    }
}
