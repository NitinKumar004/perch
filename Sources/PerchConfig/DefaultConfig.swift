import Foundation

/// The layout a brand-new user gets. It uses only **local** modules that work
/// instantly for anyone with zero setup — no personal repo, no "needs GitHub".
/// GitHub Build / Pull-requests modules are added by the user from Settings
/// once they've connected, so a fresh launch is useful and never tracks someone
/// else's repository.
public enum DefaultConfig {
    public static func make() -> LayoutConfig {
        let cpu = SlotBinding(module: "system.cpu")
        let memory = SlotBinding(module: "system.memory")
        let clock = SlotBinding(module: "system.clock")

        return LayoutConfig(
            activePreset: "default",
            presets: [
                "default": Preset(leftPill: cpu, rightPill: clock, panel: [cpu, memory]),
            ],
            hudPosition: "flank"
        )
    }
}
