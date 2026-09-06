import Foundation
import PerchCore

/// The app's own version, read from the built bundle (injected at package time)
/// with a dev fallback for `swift run`.
enum PerchVersion {
    static var current: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0-dev"
    }
}

/// An available newer release.
struct UpdateInfo: Sendable, Equatable {
    let version: String
    let pageURL: String
}

/// Checks GitHub Releases for a newer Perch and reports it. This is the honest
/// fit for the unsigned, `curl | bash` distribution: Perch can't silently
/// self-update (no signing), so it points the user at the one-line reinstall —
/// no Sparkle, no code-signing dependency.
struct UpdateChecker: Sendable {
    /// Public "latest release" endpoint — no auth needed for a public repo.
    private let latestURL = URL(string: "https://api.github.com/repos/NitinKumar004/perch/releases/latest")!
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    /// Return the latest release if it's newer than the running version, else
    /// nil. Any network/parse error is swallowed as "no update" — an update
    /// check must never interrupt the user with an error.
    func check(currentVersion: String = PerchVersion.current) async -> UpdateInfo? {
        var request = URLRequest(url: latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Perch", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let release = try? JSONDecoder().decode(Release.self, from: data) else {
            return nil
        }
        guard SemanticVersion.isNewer(release.tagName, than: currentVersion) else { return nil }
        let page = release.htmlURL ?? "https://github.com/NitinKumar004/perch/releases/latest"
        return UpdateInfo(version: release.tagName, pageURL: page)
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String?
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
