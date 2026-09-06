import Foundation

/// Reads the token from the user's GitHub CLI (`gh`) login, so they can sign in
/// with one click — no PAT to create, no device flow — and Perch inherits the
/// CLI's full access (including private org repos).
enum GitHubCLI {
    enum Outcome: Sendable {
        case token(String)
        case notInstalled   // `gh` isn't on PATH
        case notLoggedIn    // `gh` present but no auth / empty token
    }

    /// Runs `gh auth token` in a login shell (so the user's PATH — Homebrew etc.
    /// — is loaded, which a GUI app otherwise lacks). Blocking; call off the main
    /// thread.
    static func fetchToken() -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "gh auth token"]
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do { try process.run() } catch { return .notInstalled }
        process.waitUntilExit()

        let token = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            let errText = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return errText.contains("command not found") ? .notInstalled : .notLoggedIn
        }
        return token.isEmpty ? .notLoggedIn : .token(token)
    }
}
