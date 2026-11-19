/// Python docstring sections in Google (`Args:`), NumPy (`Parameters` over a dashed line), and reST
/// (`:param x:`) styles.
enum PythonDocParser {
    private static let googleParameterHeaders: Set<String> = ["args:", "arguments:", "parameters:", "params:"]
    private static let googleReturnHeaders: Set<String> = ["returns:", "return:", "yields:", "yield:"]
    private static let numpyParameterHeaders: Set<String> = ["parameters", "other parameters"]
    private static let numpyReturnHeaders: Set<String> = ["returns", "yields"]
    private static let namePattern = #"^\s*(\*{0,2}[A-Za-z_][A-Za-z0-9_]*)\s*(\([^)]*\))?\s*:"#

    /// Parses a docstring's lines.
    ///
    /// - Parameter lines: The docstring's lines, with their indentation.
    /// - Returns: What it documents; a parameter section whose entries can't be read, such as `name -- text`
    ///   lines at the header's own indentation, makes the whole doc count as unstructured.
    static func parse(_ lines: [String]) -> ParsedDoc {
        let names = (googleParameters(lines) + numpyParameters(lines) + restParameters(lines)).map(unstarred)
        let returns = hasSection(lines, google: googleReturnHeaders, numpy: numpyReturnHeaders)
            || lines.contains { DocCommentParser.matches(#"^\s*:(returns?|rtype|yields?)\b"#, $0) }
        let raises = hasSection(lines, google: ["raises:"], numpy: ["raises"])
            || lines.contains { DocCommentParser.matches(#"^\s*:raises?\b"#, $0) }
        let hasParameterSection = hasSection(lines, google: googleParameterHeaders, numpy: numpyParameterHeaders)
        let isUnreadable = hasParameterSection && names.isEmpty
        return ParsedDoc(isStructured: (!names.isEmpty || returns || raises || hasParameterSection) && !isUnreadable,
                         parameterNames: names, documentsReturn: returns, documentsThrows: raises)
    }

    /// Reads the entries under each Google-style parameter header, at the first entry's indentation.
    ///
    /// - Parameter lines: The docstring's lines.
    /// - Returns: The names, in order.
    private static func googleParameters(_ lines: [String]) -> [String] {
        headerIndices(lines, google: googleParameterHeaders).flatMap { header in
            let outer = DocCommentParser.indent(of: lines[header])
            let section = lines[(header + 1)...].filter { !isBlank($0) }
                .prefix { DocCommentParser.indent(of: $0) > outer }
            let entryIndent = section.first.map(DocCommentParser.indent(of:))
            return section.filter { DocCommentParser.indent(of: $0) == entryIndent }
                .compactMap { DocCommentParser.capture(namePattern, in: $0) }
        }
    }

    /// Reads the `name : type` entries under each NumPy-style parameter header, at the header's indentation.
    ///
    /// - Parameter lines: The docstring's lines.
    /// - Returns: The names, in order; `x, y : int` documents both.
    private static func numpyParameters(_ lines: [String]) -> [String] {
        numpyHeaderIndices(lines, numpyParameterHeaders).flatMap { header in
            let outer = DocCommentParser.indent(of: lines[header])
            let rest = Array(lines[(header + 2)...])
            let section = rest.indices.prefix { !isNumpyHeader(rest, at: $0) }.map { rest[$0] }
            return section.filter { !isBlank($0) && DocCommentParser.indent(of: $0) == outer }.flatMap(numpyNames)
        }
    }

    /// Reads the names from one NumPy entry line, such as `x, y : int` or `*args`.
    ///
    /// - Parameter line: The entry line.
    /// - Returns: The names it declares, or none if it doesn't look like an entry.
    private static func numpyNames(_ line: String) -> [String] {
        let head = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let names = head.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let isName = names.allSatisfy { DocCommentParser.matches(#"^\*{0,2}[A-Za-z_][A-Za-z0-9_]*$"#, $0) }
        return isName ? names : []
    }

    /// Reads every reST `:param name:` or `:param type name:` field.
    ///
    /// - Parameter lines: The docstring's lines.
    /// - Returns: The names, in order.
    private static func restParameters(_ lines: [String]) -> [String] {
        lines.compactMap { DocCommentParser.capture(#"^\s*:param\s+(?:[^:]*\s)?(\*{0,2}[A-Za-z_]\w*)\s*:"#, in: $0) }
    }

    /// Reports whether a docstring has a Google- or NumPy-style section with one of the given headers.
    ///
    /// - Parameters:
    ///   - lines: The docstring's lines.
    ///   - google: Google-style headers, lowercased with their colon.
    ///   - numpy: NumPy-style headers, lowercased.
    /// - Returns: Whether such a section exists.
    private static func hasSection(_ lines: [String], google: Set<String>, numpy: Set<String>) -> Bool {
        !headerIndices(lines, google: google).isEmpty || !numpyHeaderIndices(lines, numpy).isEmpty
    }

    /// Finds the lines that are exactly one of the given Google-style headers.
    ///
    /// - Parameters:
    ///   - lines: The docstring's lines.
    ///   - google: The headers, lowercased with their colon.
    /// - Returns: Their indices.
    private static func headerIndices(_ lines: [String], google: Set<String>) -> [Int] {
        lines.indices.filter { google.contains(lines[$0].trimmingCharacters(in: .whitespaces).lowercased()) }
    }

    /// Finds the NumPy-style headers among the given names: the name alone, over a line of dashes.
    ///
    /// - Parameters:
    ///   - lines: The docstring's lines.
    ///   - names: The header names, lowercased.
    /// - Returns: Their indices.
    private static func numpyHeaderIndices(_ lines: [String], _ names: Set<String>) -> [Int] {
        lines.indices.filter {
            isNumpyHeader(lines, at: $0) && names.contains(lines[$0].trimmingCharacters(in: .whitespaces).lowercased())
        }
    }

    /// Reports whether a line is a NumPy-style section header: text over a line of three or more dashes.
    ///
    /// - Parameters:
    ///   - lines: The docstring's lines.
    ///   - index: The line to check.
    /// - Returns: Whether it heads a section.
    private static func isNumpyHeader(_ lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count, !isBlank(lines[index]) else { return false }
        return DocCommentParser.matches(#"^\s*-{3,}\s*$"#, lines[index + 1])
    }

    /// Reports whether a line is empty or only whitespace.
    ///
    /// - Parameter line: The line.
    /// - Returns: Whether it's blank.
    private static func isBlank(_ line: String) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }

    /// Drops a `*` or `**` prefix, so `*args` matches the parameter `args`.
    ///
    /// - Parameter name: A documented name.
    /// - Returns: The bare name.
    private static func unstarred(_ name: String) -> String {
        String(name.drop { $0 == "*" })
    }
}
