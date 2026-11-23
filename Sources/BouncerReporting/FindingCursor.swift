/// The opaque cursor a paged agent response hands back to fetch the next page: the offset of the next finding.
///
/// It's written as `f` and the offset in base 36, so an agent passes it back as is rather than doing
/// arithmetic on it.
public enum FindingCursor {
    /// The cursor's prefix.
    private static let prefix = "f"
    /// The offset's radix.
    private static let radix = 36

    /// Encodes an offset.
    ///
    /// - Parameter offset: Where the next page starts, in the stable finding order.
    /// - Returns: The cursor.
    public static func encode(offset: Int) -> String {
        prefix + String(max(0, offset), radix: radix)
    }

    /// Decodes a cursor.
    ///
    /// - Parameter cursor: A cursor from an earlier response.
    /// - Returns: The offset, or `nil` if the cursor isn't one this encoding made.
    public static func decode(_ cursor: String) -> Int? {
        guard cursor.hasPrefix(prefix) else { return nil }
        let digits = cursor.dropFirst(prefix.count)
        guard !digits.isEmpty, digits == digits.lowercased() else { return nil }
        return Int(digits, radix: radix).flatMap { $0 >= 0 ? $0 : nil }
    }
}
