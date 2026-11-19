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
        String(format: "%016llx", value(text.utf8))
    }

    /// Hashes bytes to a 64-bit value using FNV-1a.
    ///
    /// - Parameter bytes: The bytes to hash, such as a string's UTF-8 view or a slice of one.
    /// - Returns: The hash.
    public static func value<Bytes: Sequence>(_ bytes: Bytes) -> UInt64 where Bytes.Element == UInt8 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
