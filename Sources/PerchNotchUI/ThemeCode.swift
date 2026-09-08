import Foundation

/// Encodes a full theme choice — base theme + accent + material + dynamic mode —
/// into one shareable string, and back. This is how a look travels between Macs:
/// copy the code, a teammate pastes it, they get the exact same HUD. A tiny
/// self-describing format (a prefix + base64 JSON) so it survives a paste and a
/// malformed one decodes to nil rather than crashing.
///
/// Pure and primitive-typed (ids + hex strings) so it needs no UI or config type
/// and is trivially testable.
public enum ThemeCode {
    private static let prefix = "perch:theme:"

    private struct Payload: Codable {
        var t: String       // theme id
        var a: String?      // accent hex
        var m: String?      // material id
        var d: String?      // dynamic mode
    }

    /// Encode the choice into `perch:theme:<base64>`.
    public static func encode(theme: String, accent: String?, material: String?, mode: String?) -> String {
        let payload = Payload(t: theme, a: accent, m: material, d: mode)
        guard let data = try? JSONEncoder().encode(payload) else { return prefix }
        return prefix + data.base64EncodedString()
    }

    /// Decode a pasted code (with or without the prefix / surrounding whitespace),
    /// or nil if it isn't a valid Perch theme code.
    public static func decode(_ raw: String) -> (theme: String, accent: String?, material: String?, mode: String?)? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        guard let data = Data(base64Encoded: s),
              let p = try? JSONDecoder().decode(Payload.self, from: data),
              !p.t.isEmpty else { return nil }
        return (p.t, p.a, p.m, p.d)
    }
}
