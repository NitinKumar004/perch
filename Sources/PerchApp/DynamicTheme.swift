import AppKit
import SwiftUI
import PerchNotchUI

/// Turns a base `ThemeStyle` into its live form for a dynamic mode — tinting from
/// the desktop wallpaper, or shifting the material by time of day. Pure functions
/// + a tiny sampler, so the app just asks "what should the theme be right now?"
enum DynamicTheme {
    /// Apply the SYNCHRONOUS dynamic modes ("daynight" / nil) to a base style —
    /// pure and cheap. The "wallpaper" mode isn't here: it needs an image decode
    /// and is handled asynchronously by the app (see `AppDelegate.applyTheme`) so
    /// it never blocks the main actor.
    static func apply(_ base: ThemeStyle, mode: String?, now: Date = Date()) -> ThemeStyle {
        switch mode {
        case "daynight":
            // Every Perch theme is dark, so instead of a light/dark palette swap we
            // shift the MATERIAL: crisp frosted glass by day, a warm accent glow at
            // night. A real, visible auto-change that suits any base theme.
            let hour = Calendar.current.component(.hour, from: now)
            let isNight = hour < 6 || hour >= 18
            return base.withMaterial(isNight ? .glow : .frosted)
        default:
            return base
        }
    }
}

/// Reads a representative accent colour from the current desktop wallpaper. Picks
/// the most *saturated* sample rather than a flat average (an average is muddy
/// grey) so the HUD borrows the wallpaper's character, not its dishwater.
enum WallpaperTint {
    static func sample() -> String? {
        // Cancellation-aware: when a newer Space switch supersedes this decode, the
        // caller cancels our task and we bail before/inside the heavy work.
        if Task.isCancelled { return nil }
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let src = NSBitmapImageRep(data: tiff) else { return nil }
        if Task.isCancelled { return nil }

        // Downsample to a small grid — cheap, and enough to find a vivid colour.
        let side = 12
        guard let small = downsampled(src, to: side) else { return nil }

        var best: (sat: CGFloat, r: Int, g: Int, b: Int)?
        for y in 0..<small.pixelsHigh {
            if Task.isCancelled { return nil }
            for x in 0..<small.pixelsWide {
                guard let c = small.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let sat = c.saturationComponent
                // Ignore near-black/near-white; prefer brightness so the accent pops.
                if c.brightnessComponent < 0.25 || sat < 0.15 { continue }
                let score = sat * c.brightnessComponent
                if best == nil || score > best!.sat {
                    best = (score, Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
                }
            }
        }
        guard let b = best else { return nil }
        return String(format: "#%02X%02X%02X", b.r, b.g, b.b)
    }

    private static func downsampled(_ rep: NSBitmapImageRep, to side: Int) -> NSBitmapImageRep? {
        guard let out = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        NSGraphicsContext.current?.imageInterpolation = .medium
        rep.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return out
    }
}
