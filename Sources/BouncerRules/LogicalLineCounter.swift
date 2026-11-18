import BouncerCore

/// Counts logical lines of code, excluding blank lines and comment-only lines.
///
/// Every LOC-based rule (`file-length`, `long-function`) uses this rather than
/// raw line counts, so a file padded with blank lines or a heavily commented
/// function isn't penalized for lines that carry no logic.
public enum LogicalLineCounter {
    /// Counts the logical lines within a range of a file.
    ///
    /// - Parameters:
    ///   - file: The file whose lines to count.
    ///   - range: The 0-indexed, inclusive line range to count within.
    ///   - profile: The language profile whose comment syntax applies.
    /// - Returns: The number of logical lines in `range`.
    public static func count(in file: SourceFile, range: ClosedRange<Int>, profile: LanguageProfile) -> Int {
        range
            .filter { $0 >= 0 && $0 < file.lines.count }
            .map { file.lines[$0] }
            .filter { LineClassifier.isLogical($0, profile: profile) }
            .count
    }

    /// Counts the logical lines across an entire file.
    ///
    /// - Parameters:
    ///   - file: The file whose lines to count.
    ///   - profile: The language profile whose comment syntax applies.
    /// - Returns: The number of logical lines in the file.
    public static func count(in file: SourceFile, profile: LanguageProfile) -> Int {
        guard !file.lines.isEmpty else { return 0 }
        return count(in: file, range: 0...(file.lines.count - 1), profile: profile)
    }
}
