import Foundation
import BouncerCore

/// Finds a file's error handlers, for `SecurityFailureRule`: brace-delimited `catch`/`@catch` clauses and promise
/// `.catch` callbacks, `if err != nil`/`if (err)` branches, and Python `except` clauses.
enum FailureHandlers {
    /// How far above a handler its `try` is looked for.
    private static let tryWindow = 40
    /// How many lines above an error branch or promise `.catch` count as the code it guards.
    private static let callWindow = 3
    /// The most lines a handler body is read across.
    private static let bodyLines = 60
    private static let braceOpening = TextMatching.regex(
        #"(?:\bcatch\b|@catch\b)[^{]*\{|\bif\b[^{]*\berr\s*!=\s*nil\s*\{|\bif\s*\(\s*(?:err|error)\s*\)\s*\{"#
    )
    private static let inlineOpening = TextMatching.regex(
        #"\.catch\(\s*(?:async\s*)?(?:\([^)]*\)|\w+)\s*=>\s*(?!\s*\{)|\bif\s*\(\s*(?:err|error)\s*\)\s*(?!\s*\{)"#
    )
    private static let exceptOpening = TextMatching.regex(#"^\s*except\b[^:]*:"#)
    private static let tryOpening = TextMatching.regex(#"\btry\b\s*[:{(]|@try\b|\bdo\s*\{"#)

    /// Lists every error handler in a file.
    ///
    /// - Parameter file: The file.
    /// - Returns: The handlers, in line order.
    static func all(in file: SourceFile) -> [FailureHandler] {
        let mask = SourceText.codeMask(of: file, profile: LanguageProfiles.profile(for: file.language))
        let code = file.lines.indices.map { mask[$0] ? codeText(of: file.lines[$0], in: file.language) : "" }
        return code.indices.compactMap { handler(at: $0, code: code) }
    }

    /// Reads a line's code: strings blanked, and a trailing `//` comment (or Python `#` comment) cut off.
    ///
    /// - Parameters:
    ///   - line: The line.
    ///   - language: The file's language.
    /// - Returns: The code part.
    private static func codeText(of line: Substring, in language: Language) -> String {
        let code = SourceText.code(of: line)
        guard language == .python, let hash = code.firstIndex(of: "#") else { return code }
        return String(code[..<hash])
    }

    /// Reads the handler opening on a line, if there is one.
    ///
    /// - Parameters:
    ///   - index: The line's 0-based index.
    ///   - code: Every line's code, with non-code lines empty.
    /// - Returns: The handler, or `nil`.
    private static func handler(at index: Int, code: [String]) -> FailureHandler? {
        let line = code[index]
        let body = matchEnd(braceOpening, line).map { braceBody(from: index, after: $0, code: code) }
            ?? matchEnd(inlineOpening, line).map { (line as NSString).substring(from: $0) }
        guard let body else { return exceptHandler(at: index, code: code) }
        return FailureHandler(line: index, guarded: guarded(at: index, code: code, line: line), body: body,
                              opening: line)
    }

    /// Reads a Python `except` clause on a line: its body is the rest of the line, or the block indented below it.
    ///
    /// - Parameters:
    ///   - index: The line's 0-based index.
    ///   - code: Every line's code.
    /// - Returns: The handler, or `nil` if the line isn't an `except`.
    private static func exceptHandler(at index: Int, code: [String]) -> FailureHandler? {
        guard let end = matchEnd(exceptOpening, code[index]) else { return nil }
        let indent = code[index].prefix(while: \.isWhitespace).count
        let below = code[(index + 1)...].prefix { $0.allSatisfy(\.isWhitespace) || indented($0, beyond: indent) }
        let body = [(code[index] as NSString).substring(from: end)] + below
        return FailureHandler(line: index, guarded: guarded(at: index, code: code, line: code[index]),
                              body: body.joined(separator: "\n"), opening: code[index])
    }

    /// Reports whether a line is indented further than a given width.
    ///
    /// - Parameters:
    ///   - line: The line.
    ///   - width: The width to compare against.
    /// - Returns: Whether its leading whitespace is wider.
    private static func indented(_ line: String, beyond width: Int) -> Bool {
        line.prefix(while: \.isWhitespace).count > width
    }

    /// Collects the code a handler guards: from the nearest `try` above up to a `catch` or `except` clause, or the
    /// few lines above an error branch or promise `.catch` through its own line.
    ///
    /// - Parameters:
    ///   - index: The handler's 0-based line.
    ///   - code: Every line's code.
    ///   - line: The handler line's code.
    /// - Returns: The guarded code, joined.
    private static func guarded(at index: Int, code: [String], line: String) -> String {
        let isClause = line.contains("catch") && !line.contains(".catch") || line.contains("except")
        let above = isClause ? max(0, index - tryWindow) : max(0, index - callWindow)
        guard isClause else { return code[above...index].joined(separator: "\n") }
        // A clause's own line names the error it catches (`except PermissionError`), not the check it guards.
        let start = code[above...index].lastIndex { TextMatching.matches(tryOpening, $0) } ?? above
        return code[start..<index].joined(separator: "\n")
    }

    /// Reads a brace-delimited body, from just after its `{` to the matching `}`.
    ///
    /// - Parameters:
    ///   - index: The 0-based line the `{` is on.
    ///   - offset: The UTF-16 offset just past the `{`.
    ///   - code: Every line's code.
    /// - Returns: The body's code, or everything read if it doesn't close within `bodyLines`.
    private static func braceBody(from index: Int, after offset: Int, code: [String]) -> String {
        let rest = [(code[index] as NSString).substring(from: offset)]
            + code[(index + 1)..<min(code.count, index + bodyLines)]
        let text = rest.joined(separator: "\n")
        var depth = 1
        let end = text.firstIndex { char in
            if char == "{" { depth += 1 } else if char == "}" { depth -= 1 }
            return depth == 0
        }
        return String(text[..<(end ?? text.endIndex)])
    }

    /// Finds where a pattern's first match on a line ends.
    ///
    /// - Parameters:
    ///   - regex: The pattern.
    ///   - line: The line's code.
    /// - Returns: The UTF-16 offset just past the match, or `nil` if it doesn't match.
    private static func matchEnd(_ regex: NSRegularExpression?, _ line: String) -> Int? {
        let range = NSRange(location: 0, length: (line as NSString).length)
        return regex?.firstMatch(in: line, range: range).map { NSMaxRange($0.range) }
    }
}
