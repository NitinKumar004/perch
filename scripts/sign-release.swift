// Signs a release asset with the maintainer's Ed25519 private key, producing a
// detached base64 signature the app verifies (via UpdateSignature) before it
// ever installs an update. Run by release.yml on the macOS runner — Swift +
// CryptoKit are already present, so there's no extra dependency.
//
// Usage:  PERCH_UPDATE_PRIVATE_KEY=<base64> swift scripts/sign-release.swift <file> <out.sig>
//
// The private key comes ONLY from the environment (a GitHub Actions secret) —
// never a file, never the repo. The matching public key is baked into the app in
// Sources/PerchApp/UpdateSignature.swift.
import CryptoKit
import Foundation

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 3 else { die("usage: sign-release.swift <input-file> <output-sig>") }
let inputPath = args[1], outputPath = args[2]

guard let keyBase64 = ProcessInfo.processInfo.environment["PERCH_UPDATE_PRIVATE_KEY"], !keyBase64.isEmpty else {
    die("PERCH_UPDATE_PRIVATE_KEY is not set (add it as a GitHub Actions secret)")
}
guard let keyData = Data(base64Encoded: keyBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
      let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) else {
    die("PERCH_UPDATE_PRIVATE_KEY is not a valid base64 Ed25519 private key")
}
guard let payload = FileManager.default.contents(atPath: inputPath) else {
    die("cannot read \(inputPath)")
}

do {
    let signature = try privateKey.signature(for: payload)
    // Sanity: verify against our own public key before publishing.
    guard privateKey.publicKey.isValidSignature(signature, for: payload) else { die("self-verify failed") }
    let base64 = signature.base64EncodedString()
    try base64.write(toFile: outputPath, atomically: true, encoding: .utf8)
    print("signed \(inputPath) -> \(outputPath)")
    print("public key: \(privateKey.publicKey.rawRepresentation.base64EncodedString())")
} catch {
    die("signing failed: \(error)")
}
