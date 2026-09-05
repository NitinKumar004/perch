import Foundation

/// The layout a brand-new user gets: a couple of sensible presets so the notch
/// is useful the moment the app starts, before they've customised anything.
public enum DefaultConfig {
    public static func make() -> LayoutConfig {
        let builds = SlotBinding(
            module: "github.builds",
            settings: ["repo": "NitinKumar004/perch", "branch": "main"]
        )
        let prs = SlotBinding(
            module: "github.prs",
            settings: ["queue": "review-requested"]
        )
        let clock = SlotBinding(module: "system.clock")

        return LayoutConfig(
            activePreset: "default",
            presets: [
                "default": Preset(leftPill: builds, rightPill: prs, panel: [builds, prs]),
                "minimal": Preset(leftPill: builds, rightPill: clock),
            ]
        )
    }
}
