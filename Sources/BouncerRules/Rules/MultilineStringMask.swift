import BouncerCore

/// Marks the lines that lie inside a multi-line string: a Swift `"""` literal (raw ones included), a Python
/// triple-quoted string, or a JavaScript template literal.
enum MultilineStringMask {
    private static let swiftOpener = TextMatching.regex(#"(#*)"""\s*$"#)
    private static let tripleQuote = "\"\"\""

    /// Marks each line that starts inside a multi-line string, including the line that closes it, so its text and
    /// indentation are string content rather than code.
    ///
    /// - Parameter file: The file to scan.
    /// - Returns: One flag per line.
    static func interiorLines(of file: SourceFile) -> [Bool] {
        file.language == .swift ? swiftInterior(of: file) : toggledInterior(of: file)
    }

    /// Marks Swift multi-line string lines: a `"""` (with any `#`s) ending a line opens one, and only a `"""`
    /// followed by the same number of `#`s closes it, so quotes inside a raw string don't.
    ///
    /// - Parameter file: The Swift file to scan.
    /// - Returns: One flag per line.
    private static func swiftInterior(of file: SourceFile) -> [Bool] {
        var closer: String?
        return file.lines.map { line in
            let wasInside = closer != nil
            closer = swiftCloser(after: line, current: closer)
            return wasInside
        }
    }

    /// Works out which delimiter closes the Swift string open after a line.
    ///
    /// - Parameters:
    ///   - line: The line just read.
    ///   - current: The delimiter that closes the string open before it, or `nil` outside a string.
    /// - Returns: The delimiter that closes the string open after it, or `nil` outside a string.
    private static func swiftCloser(after line: Substring, current: String?) -> String? {
        if let current { return line.contains(current) ? nil : current }
        return TextMatching.captures(swiftOpener, line).first.map { tripleQuote + $0[1] }
    }

    /// Marks lines inside triple-quoted strings and (in TypeScript and JavaScript) template literals, by an odd
    /// count of delimiters on a line toggling the state.
    ///
    /// - Parameter file: The file to scan.
    /// - Returns: One flag per line.
    private static func toggledInterior(of file: SourceFile) -> [Bool] {
        let isScript = file.language == .typescript || file.language == .javascript
        let delimiters = [tripleQuote, "'''"] + (isScript ? ["`"] : [])
        var inside = false
        return file.lines.map { line in
            let wasInside = inside
            if togglesString(line, delimiters: delimiters) { inside.toggle() }
            return wasInside
        }
    }

    /// Reports whether a line opens or closes a multi-line string, by an odd count of its delimiters.
    ///
    /// - Parameters:
    ///   - line: The line to check.
    ///   - delimiters: The string delimiters that may span lines.
    /// - Returns: Whether the line toggles multi-line-string state.
    private static func togglesString(_ line: Substring, delimiters: [String]) -> Bool {
        let count = delimiters.reduce(0) { $0 + line.components(separatedBy: $1).count - 1 }
        return count % 2 == 1
    }
}
