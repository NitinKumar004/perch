import Foundation

/// Static metadata a module declares about itself.
///
/// The registry, the settings UI and the config validator all read this — it is
/// how the app knows a module exists, what it is called, and where it may live,
/// without instantiating or running it.
public struct ModuleDescriptor: Sendable, Equatable {
    /// Stable, namespaced identifier, e.g. `"github.builds"`. Persisted in the
    /// user's layout, so it must never change once shipped.
    public let id: String
    /// Human-readable name shown in settings.
    public let name: String
    /// One-line description for the module picker.
    public let summary: String
    /// The slots this module is willing to render into.
    public let supportedSlots: Set<Slot>
    /// Whether the module needs an external connection (drives the "Connect…"
    /// affordance) or runs fully locally with zero setup.
    public let requiresConnection: Bool

    public init(
        id: String,
        name: String,
        summary: String,
        supportedSlots: Set<Slot>,
        requiresConnection: Bool
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.supportedSlots = supportedSlots
        self.requiresConnection = requiresConnection
    }
}
