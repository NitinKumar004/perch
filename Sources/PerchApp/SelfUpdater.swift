import AppKit
import Foundation

/// Installs a newer Perch in place, the same way `get.sh` does — download the
/// release zip, unpack it, and swap the app bundle — but triggered from inside
/// the app. This is the honest auto-update path for unsigned distribution:
/// Sparkle's silent update needs code-signing + an EdDSA-signed appcast, which
/// we deliberately don't have. A curl-style download isn't quarantined, so the
/// swapped-in app launches without a Gatekeeper prompt.
///
/// The actual swap runs in a short detached shell that waits for this process to
/// exit first (you can't overwrite a running bundle), then relaunches — exactly
/// the installer's proven sequence.
@MainActor
enum SelfUpdater {
    enum Result: Equatable {
        case unsupported   // running unbundled (swift run) — nothing to swap
        case failed(String)
        case relaunching   // handed off to the swap script; app is quitting
    }

    /// Download `zipURL` and swap this bundle for it. On success the app quits
    /// and the detached script relaunches the new copy.
    static func installUpdate(from zipURL: URL) async -> Result {
        guard let bundleURL = bundleAppURL() else { return .unsupported }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("perch-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            // Download the zip.
            let (downloaded, response) = try await URLSession.shared.download(from: zipURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .failed("download failed")
            }
            let zipPath = tmp.appendingPathComponent("Perch.zip")
            try? FileManager.default.removeItem(at: zipPath)
            try FileManager.default.moveItem(at: downloaded, to: zipPath)

            // Unpack with ditto (handles the app bundle's symlinks correctly).
            try run("/usr/bin/ditto", ["-x", "-k", zipPath.path, tmp.path])
            let newApp = tmp.appendingPathComponent("Perch.app")
            guard FileManager.default.fileExists(atPath: newApp.path) else {
                return .failed("archive didn't contain Perch.app")
            }

            // Hand the swap to a detached shell that waits for us to exit.
            try launchSwapScript(newApp: newApp.path, dest: bundleURL.path, pid: getpid())
            NSApp.terminate(nil)
            return .relaunching
        } catch {
            return .failed("\(error.localizedDescription)")
        }
    }

    /// The path of the running `.app` bundle, or nil under `swift run`.
    static func bundleAppURL() -> URL? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        let url = Bundle.main.bundleURL
        return url.pathExtension == "app" ? url : nil
    }

    /// The shell that performs the swap after this process exits, then relaunches.
    /// Kept as a single string so it's unit-testable without running it. Paths are
    /// safely single-quoted (any embedded quote is escaped), and if the swap fails
    /// (e.g. a non-writable install dir) it opens the release page so the user
    /// isn't left with a missing app and no feedback.
    static func swapScript(newApp: String, dest: String, pid: Int32,
                           fallbackURL: String = "https://github.com/NitinKumar004/perch/releases/latest") -> String {
        let d = shellQuote(dest), n = shellQuote(newApp), f = shellQuote(fallbackURL)
        return """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        if rm -rf \(d) && ditto \(n) \(d); then
          open \(d)
        else
          open \(f)
        fi
        """
    }

    /// POSIX-safe single-quote for a shell argument: wrap in '…', and turn any
    /// embedded ' into '\''.
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func launchSwapScript(newApp: String, dest: String, pid: Int32) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", swapScript(newApp: newApp, dest: dest, pid: pid)]
        try process.run()   // detached — outlives us on purpose
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
