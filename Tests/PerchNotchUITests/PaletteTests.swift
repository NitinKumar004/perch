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

    @Test func themesAreFullIdentitiesNotJustColour() {
        // A theme is colour + typeface + shape + material. Assert the presets
        // actually vary across those axes — a regression that flattened them all
        // to the same font/shape/material (back to "just colour") is caught.
        let faces = Set(Theme.allCases.map { $0.style.typeface })
        let materials = Set(Theme.allCases.map { $0.style.material })
        let corners = Set(Theme.allCases.map { $0.style.cornerScale })
        #expect(faces.count > 1, "every theme uses the same typeface")
        #expect(materials.count > 1, "every theme uses the same material")
        #expect(corners.count > 1, "every theme uses the same corner shape")
        // Terminal is the sharp mono one; Midnight the soft rounded glow — the two
        // ends of the identity range, so the extremes are wired.
        #expect(Theme.terminal.style.typeface == .monospaced)
        #expect(Theme.terminal.style.cornerScale < 1)
        #expect(Theme.midnight.style.typeface == .rounded)
        #expect(Theme.midnight.style.material == .glow)
    }

    @Test func everyThemeExposesATagline() {
        for t in Theme.allCases { #expect(!t.tagline.isEmpty) }
    }
}

@Suite struct ThemeStyleTests {
    @Test func radiusScalesAndClamps() {
        let sharp = ThemeStyle(palette: .system, cornerScale: 0.25)
        let round = ThemeStyle(palette: .system, cornerScale: 1.5)
        #expect(sharp.radius(8) == 2)          // 8 * 0.25
        #expect(round.radius(8) == 12)         // 8 * 1.5
        // Never negative, never absurd (capped at base*3).
        #expect(ThemeStyle(palette: .system, cornerScale: -5).radius(10) == 0)
        #expect(ThemeStyle(palette: .system, cornerScale: 100).radius(10) == 30)
    }

    @Test func withAccentAndMaterialChangeOnlyThatField() {
        let base = ThemeStyle(palette: .system, typeface: .monospaced, cornerScale: 1, material: .solid)
        let accented = base.withAccent(.blue)
        #expect(accented.palette.accent == Color.blue)
        #expect(accented.typeface == base.typeface)          // untouched
        #expect(accented.palette.surface == base.palette.surface)
        let glowed = base.withMaterial(.glow)
        #expect(glowed.material == .glow)
        #expect(glowed.palette == base.palette)              // untouched
    }
}

@Suite struct ColorHexTests {
    @Test func parsesValidForms() {
        #expect(Color(hex: "#FF0000") == Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1))
        #expect(Color(hex: "00FF00") == Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1))
        #expect(Color(hex: "#f00") == Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1))  // 3-digit
    }
    @Test func rejectsMalformed() {
        #expect(Color(hex: "") == nil)
        #expect(Color(hex: "#12") == nil)
        #expect(Color(hex: "nothex!") == nil)
        #expect(Color(hex: "#GGGGGG") == nil)
    }
}

@Suite struct ThemeResolverTests {
    @Test func noOverridesReturnsTheBaseStyle() {
        #expect(ThemeResolver.resolve(themeID: "midnight", accentHex: nil, material: nil) == Theme.midnight.style)
        // Unknown theme id → system, never crash.
        #expect(ThemeResolver.resolve(themeID: "nope", accentHex: nil, material: nil) == Theme.system.style)
    }
    @Test func accentAndMaterialOverridesApply() {
        let r = ThemeResolver.resolve(themeID: "system", accentHex: "#FF0000", material: "glow")
        #expect(r.palette.accent == Color(hex: "#FF0000"))
        #expect(r.material == .glow)
        // The rest of the base palette is untouched by the accent override.
        #expect(r.palette.surface == Theme.system.style.palette.surface)
    }
    @Test func blankOrInvalidOverridesAreIgnored() {
        let base = Theme.nord.style
        #expect(ThemeResolver.resolve(themeID: "nord", accentHex: "", material: "").palette.accent == base.palette.accent)
        #expect(ThemeResolver.resolve(themeID: "nord", accentHex: "garbage", material: "garbage") == base)
    }
}

@Suite struct ThemeCodeTests {
    @Test func roundTrips() {
        let code = ThemeCode.encode(theme: "midnight", accent: "#7C9FFF", material: "glow", mode: "wallpaper")
        #expect(code.hasPrefix("perch:theme:"))
        let d = ThemeCode.decode(code)
        #expect(d?.theme == "midnight")
        #expect(d?.accent == "#7C9FFF")
        #expect(d?.material == "glow")
        #expect(d?.mode == "wallpaper")
        // Nil optionals survive the round-trip too.
        let bare = ThemeCode.decode(ThemeCode.encode(theme: "nord", accent: nil, material: nil, mode: nil))
        #expect(bare?.theme == "nord")
        #expect(bare?.accent == nil)
    }
    @Test func toleratesWhitespaceAndMissingPrefix() {
        let code = ThemeCode.encode(theme: "terminal", accent: nil, material: nil, mode: nil)
        let stripped = String(code.dropFirst("perch:theme:".count))
        #expect(ThemeCode.decode("  \(stripped)  ")?.theme == "terminal")   // no prefix + whitespace
    }
    @Test func malformedDecodesToNil() {
        #expect(ThemeCode.decode("") == nil)
        #expect(ThemeCode.decode("perch:theme:not-base64!!") == nil)
        #expect(ThemeCode.decode("hello world") == nil)
    }
}

@Suite struct MarqueeTimingTests {
    @Test func noOverflowMeansNoScrollTime() {
        #expect(MarqueeTiming.revealSeconds(overflow: 0) == 0)
        #expect(MarqueeTiming.revealSeconds(overflow: -50) == 0)
        // A short banner message fits the slot → no reveal time.
        #expect(MarqueeTiming.bannerRevealSeconds(textLength: 10) == 0)
    }

    @Test func overflowTakesHoldPlusScrollPlusEndPause() {
        let overflow = 400.0
        let expected = MarqueeTiming.startHold + overflow / MarqueeTiming.pointsPerSecond + MarqueeTiming.endPause
        #expect(MarqueeTiming.revealSeconds(overflow: overflow) == expected)
        // Longer messages take strictly longer to reveal.
        #expect(MarqueeTiming.bannerRevealSeconds(textLength: 120) > MarqueeTiming.bannerRevealSeconds(textLength: 60))
    }
}
