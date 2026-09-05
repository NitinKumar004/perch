import Foundation

/// The set of modules the app knows about, keyed by their stable id.
///
/// The layout config references modules by id; the registry is how those ids
/// resolve to something runnable. Unknown ids simply don't resolve — the config
/// validator drops them rather than crashing.
public struct ModuleRegistry: Sendable {
    private let byID: [String: AnyNotchModule]

    public init(_ modules: [AnyNotchModule]) {
        var map: [String: AnyNotchModule] = [:]
        for module in modules {
            map[module.descriptor.id] = module
        }
        byID = map
    }

    /// Resolve a module by id, or `nil` if none is registered.
    public func module(id: String) -> AnyNotchModule? {
        byID[id]
    }

    /// Every registered module, for the settings picker.
    public var all: [AnyNotchModule] {
        Array(byID.values)
    }
}
