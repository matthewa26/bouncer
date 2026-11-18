import Foundation

/// A content hash that stays the same across runs and platforms.
///
/// Swift's built-in `hashValue` is seeded randomly per process, which makes it
/// useless for a baseline fingerprint that needs to compare equal between one
/// `bouncer` invocation and the next. FNV-1a is simple enough to hand-roll
/// without pulling in a cryptography dependency for something that only needs
/// to be stable, not secure.
public enum StableHash {
    /// Hashes a string to a fixed-width hex digest using FNV-1a.
    ///
    /// - Parameter text: The text to hash.
    /// - Returns: A 16-character lowercase hex string.
    public static func hex(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(format: "%016llx", hash)
    }
}
