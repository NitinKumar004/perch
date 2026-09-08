import Testing
import Foundation
@testable import PerchApp
@testable import PerchNotchUI

@Suite struct DynamicThemeTests {
    private func date(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
    }

    @Test func nilModeReturnsTheBaseUnchanged() {
        let base = Theme.midnight.style
        #expect(DynamicTheme.apply(base, mode: nil, now: date(hour: 3)) == base)
        #expect(DynamicTheme.apply(base, mode: "unknown-mode", now: date(hour: 3)) == base)
    }

    @Test func dayNightShiftsMaterialByHour() {
        let base = Theme.system.style   // .solid to start
        // Night (before 06:00 / from 18:00) → warm glow; day → crisp frosted.
        #expect(DynamicTheme.apply(base, mode: "daynight", now: date(hour: 23)).material == .glow)
        #expect(DynamicTheme.apply(base, mode: "daynight", now: date(hour: 5)).material == .glow)
        #expect(DynamicTheme.apply(base, mode: "daynight", now: date(hour: 12)).material == .frosted)
        #expect(DynamicTheme.apply(base, mode: "daynight", now: date(hour: 6)).material == .frosted)
        // Only the material changes — colour/typeface stay the base theme's.
        let d = DynamicTheme.apply(base, mode: "daynight", now: date(hour: 12))
        #expect(d.palette == base.palette)
        #expect(d.typeface == base.typeface)
    }
}
