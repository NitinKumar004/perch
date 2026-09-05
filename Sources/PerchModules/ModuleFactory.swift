import Foundation
import PerchModuleKit
import PerchGitHub
import PerchConfig

/// Turns a config `SlotBinding` (a module id + settings) into a runnable module.
///
/// This is the bridge between "what the user configured" and "an actual module
/// instance". It is the one place that knows how to construct each module from
/// its settings — so adding a configurable module means adding one case here,
/// and nothing in the app or the config engine changes.
public struct ModuleFactory: Sendable {
    private let apiClient: GitHubAPIClient

    public init(apiClient: GitHubAPIClient) {
        self.apiClient = apiClient
    }

    /// Build the module named by `binding`, applying its settings, or `nil` if
    /// the id is unknown (the caller drops it with a warning — never crashes).
    public func makeModule(for binding: SlotBinding) -> AnyNotchModule? {
        switch binding.module {
        case GitHubBuildsModule.descriptor.id:
            let repo = binding.settings["repo"] ?? "NitinKumar004/perch"
            let branch = binding.settings["branch"] ?? "main"
            let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return AnyNotchModule(GitHubBuildsModule(
                client: apiClient, owner: parts[0], repo: parts[1], branch: branch))

        case GitHubPRsModule.descriptor.id:
            return AnyNotchModule(GitHubPRsModule(client: apiClient))

        case VitalsModule.descriptor.id:
            return AnyNotchModule(VitalsModule())

        case ClockModule.descriptor.id:
            return AnyNotchModule(ClockModule())

        case FakeBuildModule.descriptor.id:
            return AnyNotchModule(FakeBuildModule())

        default:
            return nil
        }
    }
}
