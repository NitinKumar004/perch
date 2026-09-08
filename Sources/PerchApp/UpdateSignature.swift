import CryptoKit
import Foundation

/// Verifies that a downloaded update was signed by the holder of Perch's private
/// key before it's ever installed — the real protection a `curl | bash`,
/// unsigned distribution otherwise lacks. HTTPS only proves the bytes arrived
/// intact from *some* server; an Ed25519 signature proves they were authorised by
/// whoever holds the private key (the maintainer), which nobody who merely swaps
/// the release asset can forge.
///
/// The PUBLIC key is baked in here (safe to publish — it can only *check* a
/// signature, never create one). The matching PRIVATE key lives only as a CI
/// secret and signs `Perch.zip` at release time, producing `Perch.zip.sig`.
enum UpdateSignature {
    /// Base64 of the raw Ed25519 (Curve25519) public key. Rotating the key = ship
    /// a new value here and sign future releases with the new private key.
    static let publicKeyBase64 = "+GPXXR7gzX+ZNxm8Xg0xb7g3JA/eqcaiDqbwyIYmz0I="

    /// Whether signature checking is active — true whenever the baked key parses,
    /// which it always does in a released build. The `false` branch exists only so
    /// a malformed/removed key can't *crash*; it must never be relied on as a way
    /// to skip verification in production (the key is a compile-time constant, so
    /// an attacker can't turn it off).
    static var isEnabled: Bool { publicKey != nil }

    private static var publicKey: Curve25519.Signing.PublicKey? {
        key(fromBase64: publicKeyBase64)
    }

    /// The single security gate: may a downloaded update install? Fail CLOSED —
    /// when a key is configured, both the zip bytes and a signature that verifies
    /// them are required; a missing sig, missing bytes, or a bad signature all
    /// deny. With no key configured verification is off (a dev/fork build with the
    /// constant removed) and it allows — production always ships a real key.
    static func allowInstall(zipData: Data?, signatureBase64: String?) -> Bool {
        guard let publicKey else { return true }   // no key → checking disabled
        return allowInstall(zipData: zipData, signatureBase64: signatureBase64,
                            publicKey: publicKey, enabled: true)
    }

    /// Pure core with injected key + enabled flag, so every branch of the gate is
    /// unit-testable with a fixture keypair (no dependency on the baked key).
    static func allowInstall(zipData: Data?, signatureBase64: String?,
                             publicKey: Curve25519.Signing.PublicKey, enabled: Bool) -> Bool {
        guard enabled else { return true }
        guard let zipData, let signatureBase64 else { return false }
        return verify(zipData, signatureBase64: signatureBase64, publicKey: publicKey)
    }

    /// Verify `data` against `signatureBase64` using the baked-in public key.
    /// Returns false on any malformed input — fail closed, never crash.
    static func verify(_ data: Data, signatureBase64: String) -> Bool {
        guard let publicKey else { return false }
        return verify(data, signatureBase64: signatureBase64, publicKey: publicKey)
    }

    /// Pure core, injectable public key — so the rule is unit-testable with a
    /// fixture keypair without depending on the baked production key.
    static func verify(_ data: Data, signatureBase64: String,
                       publicKey: Curve25519.Signing.PublicKey) -> Bool {
        guard let signature = Data(base64Encoded: signatureBase64) else { return false }
        return publicKey.isValidSignature(signature, for: data)
    }

    /// Parse a base64 raw Ed25519 public key, or nil if malformed / a placeholder.
    static func key(fromBase64 base64: String) -> Curve25519.Signing.PublicKey? {
        guard let raw = Data(base64Encoded: base64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return nil }
        return key
    }
}
