import Testing
import Foundation
@testable import PerchApp

/// Centring math for Perch's auxiliary windows, so each opens centred on
/// whatever screen the user is actually on (not always the main display).
@Suite struct WindowPlacementTests {
    @Test func centersWithinTheMainScreen() {
        let origin = WindowPlacement.centeredOrigin(
            of: CGSize(width: 400, height: 300),
            in: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(origin.x == 760)   // (1920-400)/2
        #expect(origin.y == 390)   // (1080-300)/2
    }

    @Test func centersRelativeToAnOffsetSecondScreen() {
        // A monitor to the right (origin 1920,0): centred on THAT screen's frame,
        // not the main one — the multi-monitor case that was landing wrong.
        let origin = WindowPlacement.centeredOrigin(
            of: CGSize(width: 500, height: 400),
            in: CGRect(x: 1920, y: 0, width: 1440, height: 900))
        #expect(origin.x == 2390)   // 1920 + (1440-500)/2
        #expect(origin.y == 250)    // (900-400)/2
    }
}
