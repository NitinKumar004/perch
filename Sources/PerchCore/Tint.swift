import Foundation

/// The semantic colour language of the HUD.
///
/// Modules speak in *meaning* (`.good`, `.critical`), never in raw colours, so
/// the shell can keep one consistent palette and the same state always reads
/// the same way. `.accent` is the brand colour and is deliberately **not** a
/// status — it never means "attention".
public enum Tint: String, Codable, Sendable {
    case neutral
    case good
    case warning
    case critical
    case info
    case accent
}
