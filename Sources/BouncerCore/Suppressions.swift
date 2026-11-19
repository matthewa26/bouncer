import Foundation

/// The findings a file's `bouncer:` comments switch off, so a rule can be silenced where it's wrong
/// without a `.bouncer` entry.
///
/// A directive is a comment (`//`, `#`, `--`, `/*`, `<!--`, or `;`) that starts with one of:
/// - `bouncer:disable-line <rules>`: the line the comment is on.
/// - `bouncer:disable-next-line <rules>`: the next line that isn't blank or another directive.
/// - `bouncer:disable <rules>` … `bouncer:enable <rules>`: every line between them, or to the end of the
///   file without an `enable`.
/// - `bouncer:disable-file <rules>`: the whole file.
///
/// Rules are listed by ID, separated by commas or spaces. Anything after ` -- ` is a free-text reason.
public struct Suppressions: Sendable {
    /// One directive's effect: the rules it silences on a span of lines.
    private struct Span: Sendable {
        let rules: Set<String>
        let lines: ClosedRange<Int>
    }

    private static let directive = try? NSRegularExpression(
        pattern: #"(?://|#|--|/\*|<!--|;)\s*bouncer:(disable-file|disable-next-line|disable-line|disable|enable)\b(.*)"#
    )
    private static let ruleID = try? NSRegularExpression(pattern: #"[A-Za-z0-9][A-Za-z0-9_-]*"#)
    private let spans: [Span]

    /// Reads a file's directives.
    ///
    /// - Parameter file: The file.
    public init(file: SourceFile) {
        guard file.contents.contains("bouncer:") else {
            spans = []
            return
        }
        let parsed = file.lines.indices.compactMap { Self.parse(file.lines[$0], line: $0 + 1) }
        spans = Self.spans(from: parsed, in: file)
    }

    /// Reports whether a directive silences a rule on a line.
    ///
    /// - Parameters:
    ///   - ruleID: The finding's rule.
    ///   - line: The finding's 1-indexed line.
    /// - Returns: Whether the finding is suppressed.
    public func suppresses(_ ruleID: String, at line: Int) -> Bool {
        spans.contains { $0.rules.contains(ruleID) && $0.lines.contains(line) }
    }

    /// One parsed directive comment.
    private struct Directive {
        let kind: String
        let rules: Set<String>
        let line: Int
    }

    /// Parses one line's directive, if it has one.
    ///
    /// - Parameters:
    ///   - text: The line.
    ///   - line: Its 1-indexed number.
    /// - Returns: The directive, or `nil` if the line has none or it names no rules.
    private static func parse(_ text: Substring, line: Int) -> Directive? {
        let string = String(text)
        let range = NSRange(string.startIndex..., in: string)
        guard let match = directive?.firstMatch(in: string, range: range),
              let kind = Range(match.range(at: 1), in: string), let tail = Range(match.range(at: 2), in: string)
        else { return nil }
        let rules = ruleIDs(in: String(string[tail]))
        return rules.isEmpty ? nil : Directive(kind: String(string[kind]), rules: rules, line: line)
    }

    /// Reads the rule IDs after a directive, stopping at a ` -- ` reason or a comment's closing marker.
    ///
    /// - Parameter tail: The text after the directive's keyword.
    /// - Returns: The rule IDs.
    private static func ruleIDs(in tail: String) -> Set<String> {
        let list = tail.components(separatedBy: " --").first?
            .components(separatedBy: "*/").first?.components(separatedBy: "-->").first ?? ""
        let range = NSRange(list.startIndex..., in: list)
        let matches = ruleID?.matches(in: list, range: range) ?? []
        return Set(matches.compactMap { Range($0.range, in: list).map { String(list[$0]) } })
    }

    /// Turns parsed directives into the line spans they cover.
    ///
    /// - Parameters:
    ///   - directives: The file's directives, in line order.
    ///   - file: The file, for its length and for finding the line after a `disable-next-line`.
    /// - Returns: The spans.
    private static func spans(from directives: [Directive], in file: SourceFile) -> [Span] {
        directives.flatMap { spans(for: $0, among: directives, in: file) }
    }

    /// Works out the spans one directive covers.
    ///
    /// - Parameters:
    ///   - directive: The directive.
    ///   - directives: Every directive in the file, to find matching `enable`s and stacked directives.
    ///   - file: The file.
    /// - Returns: Its spans; an `enable` covers none.
    private static func spans(for directive: Directive, among directives: [Directive], in file: SourceFile) -> [Span] {
        switch directive.kind {
        case "disable-line": [Span(rules: directive.rules, lines: directive.line...directive.line)]
        case "disable-next-line": [nextLineSpan(after: directive, among: directives, in: file)].compactMap { $0 }
        case "disable-file": [Span(rules: directive.rules, lines: 1...max(1, file.lines.count))]
        case "disable": directive.rules.map { rangeSpan(of: $0, from: directive, to: directives, in: file) }
        default: []
        }
    }

    /// Covers the next line after a directive that isn't blank or another directive.
    ///
    /// - Parameters:
    ///   - directive: The `disable-next-line` directive.
    ///   - directives: Every directive in the file; their lines are skipped so directives can be stacked.
    ///   - file: The file.
    /// - Returns: The span, or `nil` if no line follows.
    private static func nextLineSpan(after directive: Directive, among directives: [Directive],
                                     in file: SourceFile) -> Span? {
        let directiveLines = Set(directives.map(\.line))
        let following = (directive.line + 1..<(file.lines.count + 1)).first { line in
            !directiveLines.contains(line) && !file.lines[line - 1].allSatisfy(\.isWhitespace)
        }
        return following.map { Span(rules: directive.rules, lines: $0...$0) }
    }

    /// Covers the lines from a `disable` to the first later `enable` of one of its rules.
    ///
    /// - Parameters:
    ///   - rule: The rule.
    ///   - directive: The `disable` directive.
    ///   - directives: Every directive in the file, to find the matching `enable`.
    ///   - file: The file, for its length when nothing re-enables the rule.
    /// - Returns: The span.
    private static func rangeSpan(
        of rule: String, from directive: Directive, to directives: [Directive], in file: SourceFile
    ) -> Span {
        let enable = directives.first { $0.kind == "enable" && $0.line > directive.line && $0.rules.contains(rule) }
        let end = enable.map { $0.line - 1 } ?? file.lines.count
        return Span(rules: [rule], lines: directive.line...max(directive.line, end))
    }
}
