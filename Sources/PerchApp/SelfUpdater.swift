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
    /// and the detached script relaunches the new copy. When signature checking
    /// is active, the zip is verified against the baked-in public key BEFORE the
    /// swap — a forged/tampered release is rejected, never installed.
    static func installUpdate(from zipURL: URL, signatureURL: URL?) async -> Result {
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

            // Verify the signature before we do anything with the bytes. Fail
            // CLOSED: with a key configured, a missing/bad signature aborts the
            // install rather than trusting an unverified download.
            //
            // Scope note (accepted residual): the signature binds the zip BYTES,
            // not the version tag. An attacker who could rewrite a GitHub release's
            // assets (without holding the offline signing key) could re-attach an
            // OLD, validly-signed Perch under a newer tag — a bounded downgrade to
            // a genuine past build. Holding the private key stays the real barrier;
            // binding version+hash is a possible future hardening, not shipped here.
            if UpdateSignature.isEnabled {
                guard let signatureURL else { return .failed("update is not signed — refusing to install") }
                let sigBase64 = await fetchSignature(signatureURL)
                // Read the zip + verify off the main actor — reading a multi-MB
                // file shouldn't stall the notch UI (same reason the ditto unpack
                // is detached below).
                let zipPathString = zipPath.path
                let allowed = await Task.detached {
                    let zipData = try? Data(contentsOf: URL(fileURLWithPath: zipPathString))
                    return UpdateSignature.allowInstall(zipData: zipData, signatureBase64: sigBase64)
                }.value
                guard allowed else {
                    return .failed("update signature could not be verified — refusing to install")
                }
            }

            // Unpack with ditto (handles the app bundle's symlinks correctly).
            // Off the main actor: ditto blocks for seconds on a multi-MB bundle,
            // and freezing the run loop would hang the notch UI mid-update.
            let zipPathString = zipPath.path
            let tmpPathString = tmp.path
            try await Task.detached {
                try SelfUpdater.run("/usr/bin/ditto", ["-x", "-k", zipPathString, tmpPathString])
            }.value
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

    /// Fetch the base64 signature file (`Perch.zip.sig`), or nil on any failure.
    private static func fetchSignature(_ url: URL) async -> String? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        // The .sig file is the base64 signature (possibly with trailing newline).
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The path of the running `.app` bundle, or nil under `swift run`.
    static func bundleAppURL() -> URL? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        let url = Bundle.main.bundleURL
        return url.pathExtension == "app" ? url : nil
    }

    /// The shell that performs the swap after this process exits, then relaunches.
    /// Kept as a single string so it's unit-testable without running it. Paths are
    /// safely single-quoted (any embedded quote is escaped).
    ///
    /// Safe swap order — NEVER delete the installed app before the replacement is
    /// verified in place. Move the old bundle aside to a backup, copy the new one
    /// in; only on success drop the backup. If the copy fails, roll the backup
    /// back so the user is never left with no app (the earlier `rm -rf dest &&
    /// ditto` could delete the app and then fail the copy, leaving nothing).
    static func swapScript(newApp: String, dest: String, pid: Int32,
                           fallbackURL: String = "https://github.com/NitinKumar004/perch/releases/latest") -> String {
        let d = shellQuote(dest), n = shellQuote(newApp), f = shellQuote(fallbackURL)
        return """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        BAK=\(d).backup
        rm -rf "$BAK"
        if mv \(d) "$BAK"; then
          if ditto \(n) \(d); then
            rm -rf "$BAK"
            open \(d)
          else
            rm -rf \(d)
            mv "$BAK" \(d)
            open \(f)
          fi
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

    /// Run a subprocess to completion. `nonisolated` so callers can hop it off
    /// the main actor (ditto blocks) via `Task.detached`.
    @discardableResult
    nonisolated static func run(_ launchPath: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
