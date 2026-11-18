import BouncerCore

/// Classifies a line as blank, comment-only, or logical, per a language profile.
public enum LineClassifier {
    /// Reports whether a line has no non-whitespace content.
    ///
    /// - Parameter line: The line to check.
    /// - Returns: Whether the line is blank.
    public static func isBlank(_ line: Substring) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }

    /// Reports whether a line counts toward a logical line-of-code total.
    ///
    /// - Parameters:
    ///   - line: The line to check.
    ///   - profile: The language profile whose comment syntax applies.
    /// - Returns: Whether the line is neither blank nor comment-only.
    public static func isLogical(_ line: Substring, profile: LanguageProfile) -> Bool {
        let trimmed = line.drop { $0.isWhitespace }
        guard !isBlank(trimmed) else { return false }
        return !profile.isCommentOnly(trimmed)
    }
}
