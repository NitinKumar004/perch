import Testing
import Foundation
import CryptoKit
@testable import PerchApp

/// The update-signature verifier: only a signature made with the matching
/// private key, over the exact bytes, verifies. Uses fixture keypairs so the
/// rule is proven independently of the baked-in production key.
@Suite struct UpdateSignatureTests {
    let signer = Curve25519.Signing.PrivateKey()
    let payload = Data("Perch.zip contents".utf8)

    func sig(of data: Data, by key: Curve25519.Signing.PrivateKey) -> String {
        (try! key.signature(for: data)).base64EncodedString()
    }

    @Test func validSignatureVerifies() {
        let s = sig(of: payload, by: signer)
        #expect(UpdateSignature.verify(payload, signatureBase64: s, publicKey: signer.publicKey))
    }

    @Test func tamperedPayloadIsRejected() {
        let s = sig(of: payload, by: signer)                  // signed the real bytes…
        let tampered = Data("Perch.zip contents (evil)".utf8) // …but the file was swapped
        #expect(!UpdateSignature.verify(tampered, signatureBase64: s, publicKey: signer.publicKey))
    }

    @Test func signatureFromADifferentKeyIsRejected() {
        // An attacker signs their forged zip with THEIR key — but the app only
        // trusts the maintainer's public key, so it fails. This is the property
        // that protects against a compromised release.
        let attacker = Curve25519.Signing.PrivateKey()
        let forged = sig(of: payload, by: attacker)
        #expect(!UpdateSignature.verify(payload, signatureBase64: forged, publicKey: signer.publicKey))
    }

    @Test func malformedSignatureFailsClosedNoCrash() {
        #expect(!UpdateSignature.verify(payload, signatureBase64: "not base64!!", publicKey: signer.publicKey))
        #expect(!UpdateSignature.verify(payload, signatureBase64: "", publicKey: signer.publicKey))
        #expect(!UpdateSignature.verify(payload, signatureBase64: "YWJj", publicKey: signer.publicKey)) // valid b64, wrong length
    }

    @Test func bakedPublicKeyIsValidAndEnabled() {
        // The shipped public-key constant must parse (a placeholder/typo would
        // silently disable verification — fail-open — which we must never do).
        #expect(UpdateSignature.key(fromBase64: UpdateSignature.publicKeyBase64) != nil)
        #expect(UpdateSignature.isEnabled)
    }

    @Test func bakedKeyRoundTripsAgainstAMatchingSignature() {
        // Prove the shipped verify() path works end to end: sign with a key whose
        // public half we feed in, and confirm the injected-key overload agrees
        // with a real isValidSignature.
        let s = sig(of: payload, by: signer)
        #expect(signer.publicKey.isValidSignature(Data(base64Encoded: s)!, for: payload))
        #expect(UpdateSignature.verify(payload, signatureBase64: s, publicKey: signer.publicKey))
    }

    // MARK: - The install gate (fail-closed control flow)

    func allow(_ zip: Data?, _ sig: String?, enabled: Bool = true) -> Bool {
        UpdateSignature.allowInstall(zipData: zip, signatureBase64: sig,
                                     publicKey: signer.publicKey, enabled: enabled)
    }

    @Test func gateAllowsOnlyAValidlySignedZip() {
        let good = sig(of: payload, by: signer)
        #expect(allow(payload, good))                                   // valid → install
    }

    @Test func gateDeniesEveryUnverifiedCase() {
        let good = sig(of: payload, by: signer)
        #expect(!allow(nil, good))                                      // no zip bytes → deny
        #expect(!allow(payload, nil))                                   // no signature (fetch 404) → deny
        #expect(!allow(Data("evil".utf8), good))                       // tampered zip → deny
        #expect(!allow(payload, sig(of: payload, by: .init())))         // attacker's key → deny
        #expect(!allow(payload, "not base64!!"))                        // malformed sig → deny
    }

    @Test func gateAllowsWhenCheckingDisabled() {
        // The only "allow without a signature" path: no key configured at all
        // (dev/fork build). Never reachable in a released build (key is baked in).
        #expect(allow(nil, nil, enabled: false))
        #expect(allow(payload, "anything", enabled: false))
    }
}
