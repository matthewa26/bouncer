import Foundation
import BouncerCore

/// A language's comment syntax: its line-comment prefixes and, where it has one, its block-comment delimiters.
///
/// Line prefixes come from the `LanguageProfile`; block delimiters are keyed by language here, since the profile
/// only models line comments.
struct CommentSyntax: Sendable {
    /// The tokens that start a line comment, such as `["//"]`.
    let linePrefixes: [String]
    /// The block-comment opener, such as `"/*"`, if the language has block comments.
    let blockOpen: String?
    /// The block-comment closer matching `blockOpen`.
    let blockClose: String?
    /// An attribute's opener that starts like a line comment, such as PHP's `#[`; a line starting with it is code.
    let attributePrefix: String?

    /// Derives the comment syntax for a file's language.
    ///
    /// PHP's line comments are `//` and `#`, but not `#[`, which opens an attribute.
    ///
    /// Returns `nil` for `.other`: the best-effort profile's prefixes are guesses (`#` is also a Markdown heading),
    /// so the comment-smell rules don't run there.
    ///
    /// - Parameters:
    ///   - language: The file's detected language.
    ///   - profile: The language's profile, for its line-comment prefixes.
    init?(language: Language, profile: LanguageProfile) {
        if case .other = language { return nil }
        let delimiters = Self.blockDelimiters(for: language)
        let isPHP = language == .php
        self.linePrefixes = isPHP ? ["//", "#"] : profile.lineCommentPrefixes
        self.blockOpen = delimiters?.open
        self.blockClose = delimiters?.close
        self.attributePrefix = isPHP ? "#[" : nil
    }

    /// Looks up the block-comment delimiters for a language.
    ///
    /// - Parameter language: The language to look up.
    /// - Returns: The opener and closer, or `nil` for a language without block comments (Python, shells).
    private static func blockDelimiters(for language: Language) -> (open: String, close: String)? {
        switch language {
        case .swift, .typescript, .javascript, .cpp, .c, .objc, .java, .go, .sql, .rust, .php: return ("/*", "*/")
        case .powershell: return ("<#", "#>")
        default: return nil
        }
    }
}

/// One comment-only line: where it is, the text after its comment marker, and what kind of comment it belongs to.
struct CommentLine: Sendable {
    /// The 0-based line index in the file.
    let index: Int
    /// The text after the comment marker (and a block comment's leading `*`), untrimmed.
    let body: Substring
    /// Whether the comment is documentation (`///`, `//!`, `/** */`, `#!`, `#:`) or otherwise not prose to inspect.
    let isDoc: Bool
    /// Whether the line is part of a block comment rather than a line comment.
    let isBlock: Bool
}

/// A maximal group of adjacent comment-only lines of the same kind, with no blank or code line between them.
struct CommentRun: Sendable {
    /// The run's lines, in file order.
    var lines: [CommentLine]

    /// Whether the run is documentation, which the comment-smell rules never inspect.
    var isDoc: Bool { lines.first?.isDoc ?? false }
}

/// How `CommentScanner` classified one line.
enum ScannedLine: Sendable {
    case blank
    case code
    case comment(CommentLine)
}

/// Splits a file's lines into blank, code, and comment-only lines, tracking block comments and triple-quoted strings.
///
/// It's text-based: a block comment only counts when it opens at the start of a line, and a line inside a
/// triple-quoted string (a Python docstring, a Swift multi-line literal) is code, never a comment.
struct CommentScanner {
    private let syntax: CommentSyntax
    private var openBlockIsDoc: Bool?
    private var inTripleQuotedString = false

    /// Creates a scanner for one language's comment syntax.
    ///
    /// - Parameter syntax: The comment syntax to scan with.
    init(syntax: CommentSyntax) {
        self.syntax = syntax
    }

    /// Classifies every line of a file.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - syntax: The file's comment syntax.
    /// - Returns: One classification per line, in file order.
    static func scan(_ file: SourceFile, syntax: CommentSyntax) -> [ScannedLine] {
        var scanner = CommentScanner(syntax: syntax)
        return file.lines.enumerated().map { index, line in scanner.classify(line, index: index) }
    }

    /// Groups a file's comment-only lines into runs of adjacent lines of the same kind.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - syntax: The file's comment syntax.
    /// - Returns: The comment runs, in file order.
    static func runs(in file: SourceFile, syntax: CommentSyntax) -> [CommentRun] {
        var runs: [CommentRun] = [], previous: CommentLine?
        for case .comment(let line) in scan(file, syntax: syntax) {
            let continues = previous.map { $0.index + 1 == line.index && $0.isDoc == line.isDoc } ?? false
            if continues { runs[runs.count - 1].lines.append(line) } else { runs.append(CommentRun(lines: [line])) }
            previous = line
        }
        return runs
    }

    /// Classifies one line, updating the block-comment and string state for the lines after it.
    ///
    /// - Parameters:
    ///   - raw: The line as it appears in the file.
    ///   - index: The line's 0-based index.
    /// - Returns: The line's classification.
    mutating func classify(_ raw: Substring, index: Int) -> ScannedLine {
        let line = raw.drop { $0.isWhitespace }
        if openBlockIsDoc != nil { return .comment(continueBlock(line, index: index)) }
        let comment = inTripleQuotedString || line.isEmpty ? nil : startComment(line, index: index)
        return comment.map(ScannedLine.comment) ?? trackString(line)
    }

    /// Reads a comment that starts on this line, either a line comment or a block comment's opener.
    ///
    /// - Parameters:
    ///   - line: The line, with leading whitespace removed.
    ///   - index: The line's 0-based index.
    /// - Returns: The comment line, or `nil` if the line doesn't start with a comment.
    private mutating func startComment(_ line: Substring, index: Int) -> CommentLine? {
        if let comment = lineComment(line, index: index) { return comment }
        guard let open = syntax.blockOpen, line.hasPrefix(open) else { return nil }
        return openBlock(line, index: index)
    }

    /// Classifies a blank or code line, flipping triple-quoted-string state when the line opens or closes one.
    ///
    /// - Parameter line: The line, with leading whitespace removed.
    /// - Returns: `.blank` for an empty line outside a string, otherwise `.code`.
    private mutating func trackString(_ line: Substring) -> ScannedLine {
        if Self.togglesTripleQuote(line) { inTripleQuotedString.toggle() }
        return line.isEmpty && !inTripleQuotedString ? .blank : .code
    }

    /// Reads a line comment, if the line starts with one of the language's line-comment prefixes.
    ///
    /// - Parameters:
    ///   - line: The line, with leading whitespace removed.
    ///   - index: The line's 0-based index.
    /// - Returns: The comment line, or `nil` if the line isn't a line comment.
    private func lineComment(_ line: Substring, index: Int) -> CommentLine? {
        if let attribute = syntax.attributePrefix, line.hasPrefix(attribute) { return nil }
        guard let prefix = syntax.linePrefixes.first(where: { line.hasPrefix($0) }) else { return nil }
        let rest = line.dropFirst(prefix.count)
        let marker = rest.first
        let isDoc = marker == "!" || (prefix == "//" && marker == "/") || (prefix == "#" && marker == ":")
        return CommentLine(index: index, body: rest, isDoc: isDoc, isBlock: false)
    }

    /// Reads the first line of a block comment and, if it doesn't close on the same line, enters block state.
    ///
    /// An opener followed directly by a quote (`<#'`) is a polyglot sentinel hiding another language's script from
    /// this one; it's marked as documentation so the comment-smell rules leave it alone.
    ///
    /// - Parameters:
    ///   - line: The line, with leading whitespace removed, starting with the block opener.
    ///   - index: The line's 0-based index.
    /// - Returns: The comment line for the opener's line.
    private mutating func openBlock(_ line: Substring, index: Int) -> CommentLine {
        let rest = line.dropFirst(syntax.blockOpen?.count ?? 0)
        let isPolyglot = rest.first.map { "'\"".contains($0) } ?? false
        let isDoc = (rest.hasPrefix("*") && !rest.hasPrefix("*/")) || rest.hasPrefix("!") || isPolyglot
        let body = rest.dropFirst(isDoc ? 1 : 0)
        if let close = syntax.blockClose, let end = body.range(of: close) {
            return CommentLine(index: index, body: body[..<end.lowerBound], isDoc: isDoc, isBlock: true)
        }
        openBlockIsDoc = isDoc
        return CommentLine(index: index, body: body, isDoc: isDoc, isBlock: true)
    }

    /// Reads a line inside an open block comment, leaving block state if the line closes it.
    ///
    /// - Parameters:
    ///   - line: The line, with leading whitespace removed.
    ///   - index: The line's 0-based index.
    /// - Returns: The comment line, with any leading `*` gutter removed.
    private mutating func continueBlock(_ line: Substring, index: Int) -> CommentLine {
        let isDoc = openBlockIsDoc ?? false
        var body = line
        if let close = syntax.blockClose, let end = line.range(of: close) {
            body = line[..<end.lowerBound]
            openBlockIsDoc = nil
        }
        if body.hasPrefix("*") { body = body.dropFirst() }
        return CommentLine(index: index, body: body, isDoc: isDoc, isBlock: true)
    }

    /// Reports whether a line opens or closes a triple-quoted string, by an odd count of `"""` or `'''`.
    ///
    /// - Parameter line: The line to check.
    /// - Returns: Whether the line toggles triple-quoted-string state.
    private static func togglesTripleQuote(_ line: Substring) -> Bool {
        let doubles = line.components(separatedBy: "\"\"\"").count - 1
        let singles = line.components(separatedBy: "'''").count - 1
        return (doubles + singles) % 2 == 1
    }
}
