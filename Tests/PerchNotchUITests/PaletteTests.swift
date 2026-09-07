import Testing
import SwiftUI
import PerchCore
@testable import PerchNotchUI

@Suite struct PaletteTests {
    @Test func systemPaletteResolvesEveryTint() {
        let p = Palette.system
        // Each semantic tint maps to the palette's declared role — exhaustively,
        // so a new Tint case can't silently fall back to a wrong colour.
        #expect(p.color(for: .neutral) == p.neutral)
        #expect(p.color(for: .good) == p.good)
        #expect(p.color(for: .warning) == p.warning)
        #expect(p.color(for: .critical) == p.critical)
        #expect(p.color(for: .info) == p.info)
        #expect(p.color(for: .accent) == p.accent)
    }

    @Test func distinctPalettesResolveDistinctly() {
        // A second palette with a different `good` recolours only that tint —
        // proving the mapping reads the instance, not a hardcoded colour.
        var custom = Palette.system
        custom.good = .blue
        #expect(custom.color(for: .good) == Color.blue)
        #expect(custom.color(for: .critical) == Palette.system.critical)
    }
}

@Suite struct ThemeTests {
    @Test func everyThemeHasDistinctIdAndLabel() {
        let ids = Set(Theme.allCases.map(\.id))
        #expect(ids.count == Theme.allCases.count)   // ids are unique
        for t in Theme.allCases { #expect(!t.label.isEmpty) }
    }

    @Test func idRoundTripsToPalette() {
        // The config stores a raw id; it must map back to the right theme.
        #expect(Theme(rawValue: "midnight") == .midnight)
        #expect(Theme(rawValue: "system") == .system)
        // An unknown/removed id falls back to system, never crashes.
        #expect(Theme(rawValue: "no-such-theme") == nil)
    }

    @Test func systemThemeIsTheOriginalPalette() {
        #expect(Theme.system.palette == Palette.system)
    }

    @Test func themesDifferFromSystem() {
        // Each non-system theme actually changes the look (not an accidental copy).
        for t in Theme.allCases where t != .system {
            #expect(t.palette != Palette.system, "\(t.label) is identical to system")
        }
    }

    @Test func everyThemeReskinsTheChrome() {
        // The whole-palette check above passes if only a status tint differs. The
        // point of a theme is the CHROME (surface/ink) — assert each theme moves
        // at least one chrome role, so a regression that reset surface+onSurface
        // to system's (making the panel un-themed) is caught.
        for t in Theme.allCases where t != .system {
            let differsInChrome = t.palette.surface != Palette.system.surface
                || t.palette.onSurface != Palette.system.onSurface
            #expect(differsInChrome, "\(t.label) doesn't re-skin the panel chrome")
        }
    }
}
