import Foundation
import BouncerCore

/// What a structured doc comment documents.
public struct ParsedDoc: Sendable, Equatable {
    /// Whether the doc uses its convention's structured parts at all; a summary-only doc isn't checked.
    public let isStructured: Bool
    /// The parameter names it documents, in order, without any `*`/`**` prefix.
    public let parameterNames: [String]
    public let documentsReturn: Bool
    public let documentsThrows: Bool
}

/// Reads the parameter, return, and throws entries out of a doc comment, per `DocStyle`.
public enum DocCommentParser {
    /// Parses a doc comment.
    ///
    /// - Parameters:
    ///   - text: The comment's raw text.
    ///   - style: Its convention.
    /// - Returns: What it documents.
    public static func parse(_ text: String, style: DocStyle) -> ParsedDoc {
        switch style {
        case .swift: return SwiftDocParser.parse(lines(of: text))
        case .jsdoc: return JSDocParser.parse(lines(of: text).joined(separator: "\n"))
        case .python: return PythonDocParser.parse(SourceFile.lines(of: text).map(String.init))
        }
    }

    /// Splits a comment into lines without their `///`, `/**`, `*/`, or leading `*` markers.
    ///
    /// - Parameter text: The comment's raw text.
    /// - Returns: Its lines, with their remaining indentation.
    static func lines(of text: String) -> [String] {
        SourceFile.lines(of: text).map { line in
            var body = Substring(line.drop { $0 == " " || $0 == "\t" })
            for marker in ["///", "/**", "*/", "*"] where body.hasPrefix(marker) { body = body.dropFirst(marker.count) }
            if body.hasSuffix("*/") { body = body.dropLast(2) }
            return String(body)
        }
    }

    /// Finds the first capture group of a pattern in a string.
    ///
    /// - Parameters:
    ///   - pattern: A regular expression with one capture group.
    ///   - text: The string to search.
    /// - Returns: The captured text, or `nil` if the pattern doesn't match.
    static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// Reports whether a string matches a pattern, ignoring case.
    ///
    /// - Parameters:
    ///   - pattern: A regular expression.
    ///   - text: The string to test.
    /// - Returns: Whether it matches anywhere.
    static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Counts a line's leading spaces, with a tab as four.
    ///
    /// - Parameter line: The line.
    /// - Returns: Its indentation width.
    static func indent(of line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }
}

/// Swift's DocC callouts: `- Parameter x:`, a `- Parameters:` list, `- Returns:`, and `- Throws:`. Read with
/// plain string checks rather than regular expressions, since every documented Swift function is parsed.
private enum SwiftDocParser {
    /// One `- Callout` line: how far its dash is indented and what follows it.
    private struct Callout {
        let indent: Int
        let body: Substring

        /// Reads a line as a callout.
        ///
        /// - Parameter line: A comment line.
        init?(_ line: String) {
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            guard trimmed.first == "-" else { return nil }
            indent = DocCommentParser.indent(of: line)
            body = trimmed.dropFirst().drop { $0 == " " }
        }

        /// Reports whether the callout is a keyword such as `Returns`, followed by a colon, ignoring case.
        ///
        /// - Parameter keyword: The lowercased keyword.
        /// - Returns: Whether it matches.
        func isKeyword(_ keyword: String) -> Bool {
            body.prefix(keyword.count).lowercased() == keyword
                && body.dropFirst(keyword.count).drop { $0 == " " }.first == ":"
        }

        /// Reads a name followed by a colon at the start of some text.
        ///
        /// - Parameter text: The text after the dash or the `Parameter` keyword.
        /// - Returns: The name, or `nil` if a colon doesn't follow an identifier.
        static func name(in text: Substring) -> String? {
            let name = text.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            guard let first = name.first, !first.isNumber else { return nil }
            return text.dropFirst(name.count).drop { $0 == " " }.first == ":" ? String(name) : nil
        }
    }

    /// Parses a Swift doc comment's lines.
    ///
    /// - Parameter lines: The comment's lines, without `///` markers.
    /// - Returns: What it documents.
    static func parse(_ lines: [String]) -> ParsedDoc {
        let callouts = lines.compactMap(Callout.init)
        let returns = callouts.contains { $0.isKeyword("returns") || $0.isKeyword("return") }
        let throwing = callouts.contains { $0.isKeyword("throws") }
        let names = callouts.compactMap(singleParameter) + listedParameters(callouts)
        let hasList = callouts.contains { $0.isKeyword("parameters") }
        return ParsedDoc(
            isStructured: returns || throwing || hasList || !names.isEmpty, parameterNames: names,
            documentsReturn: returns, documentsThrows: throwing
        )
    }

    /// Reads a `- Parameter name:` callout's name.
    ///
    /// - Parameter callout: A callout.
    /// - Returns: The name, or `nil` for any other callout.
    private static func singleParameter(_ callout: Callout) -> String? {
        guard callout.body.prefix(10).lowercased() == "parameter " else { return nil }
        return Callout.name(in: callout.body.dropFirst(10).drop { $0 == " " })
    }

    /// Reads the `- name:` entries nested under each `- Parameters:` callout.
    ///
    /// - Parameter callouts: The comment's callouts.
    /// - Returns: The names, in order.
    private static func listedParameters(_ callouts: [Callout]) -> [String] {
        callouts.reduce(into: (names: [String](), listIndent: Int?.none)) { state, callout in
            if let outer = state.listIndent, callout.indent > outer {
                state.names += Callout.name(in: callout.body).map { [$0] } ?? []
            } else {
                state.listIndent = callout.isKeyword("parameters") ? callout.indent : nil
            }
        }.names
    }
}

/// JSDoc tags: `@param {Type} name`, `@param [name=default]`, `@returns`, and `@throws`.
private enum JSDocParser {
    private static let parameterTags = ["param", "arg", "argument"]

    /// Parses a JSDoc comment's text.
    ///
    /// - Parameter text: The comment's text, without `*` markers.
    /// - Returns: What it documents; a doc that inherits (`@inheritDoc`, `@override`) counts as unstructured.
    static func parse(_ text: String) -> ParsedDoc {
        let names = parameterTags.flatMap { tagBodies($0, in: text) }.compactMap(parameterName)
        let returns = DocCommentParser.matches(#"@returns?\b"#, text)
        let throwing = DocCommentParser.matches(#"@(throws|exception)\b"#, text)
        let tagged = returns || throwing || DocCommentParser.matches(#"@(param|arg|argument)\b"#, text)
        let inherits = DocCommentParser.matches(#"@(inheritdoc|override)\b"#, text)
        return ParsedDoc(
            isStructured: tagged && !inherits, parameterNames: names, documentsReturn: returns,
            documentsThrows: throwing
        )
    }

    /// Lists the text following each occurrence of a tag, such as `{string} name the name` for `@param`.
    ///
    /// - Parameters:
    ///   - tag: The tag name, without `@`.
    ///   - text: The comment's text.
    /// - Returns: Each occurrence's following text, up to the next tag.
    private static func tagBodies(_ tag: String, in text: String) -> [Substring] {
        text.components(separatedBy: "@").dropFirst().compactMap { part -> Substring? in
            guard part.hasPrefix(tag), part.dropFirst(tag.count).first?.isWhitespace == true else { return nil }
            return part.dropFirst(tag.count)
        }
    }

    /// Reads the parameter name from a `@param` tag's body, skipping a `{Type}` and unwrapping `[name=x]`.
    ///
    /// - Parameter body: The text after `@param`.
    /// - Returns: The name, or `nil` for a nested property such as `options.debug` or a missing name.
    private static func parameterName(_ body: Substring) -> String? {
        var rest = skippingType(body.drop { $0.isWhitespace }).drop { $0.isWhitespace }
        if rest.hasPrefix("[") { rest = rest.dropFirst().prefix { $0 != "]" && $0 != "=" } }
        let name = String(rest.drop { $0 == "." }.prefix { $0.isLetter || $0.isNumber || "_$.".contains($0) })
        return name.isEmpty || name.contains(".") ? nil : name
    }

    /// Drops a leading `{Type}`, matching nested braces.
    ///
    /// - Parameter text: Text that may start with a type in braces.
    /// - Returns: The text after the type, or the text unchanged if it has none.
    private static func skippingType(_ text: Substring) -> Substring {
        guard text.hasPrefix("{") else { return text }
        var depth = 0
        for index in text.indices {
            depth += text[index] == "{" ? 1 : text[index] == "}" ? -1 : 0
            if depth == 0 { return text[text.index(after: index)...] }
        }
        return ""
    }
}
