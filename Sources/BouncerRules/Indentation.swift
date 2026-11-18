/// Measures a line's leading whitespace as a comparable indentation depth.
public enum Indentation {
    /// Computes a line's indentation depth, treating a tab as `tabWidth` spaces.
    ///
    /// - Parameters:
    ///   - line: The line to measure.
    ///   - tabWidth: How many depth units one tab counts as.
    /// - Returns: The number of leading whitespace units.
    public static func depth(of line: Substring, tabWidth: Int = 4) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? tabWidth : 1) }
    }
}
