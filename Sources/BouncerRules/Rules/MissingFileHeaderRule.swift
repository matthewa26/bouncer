import Foundation
import BouncerCore

/// Flags a file that doesn't open with a header comment, or whose header doesn't match a required pattern (such as a
/// license line).
///
/// Opt-in. A shebang, blank lines, and leading tool directives (`// swift-tools-version`, `//go:build`,
/// `// +build`, `# -*- coding`, `"use strict"`) are skipped; the first line after them must start a comment, or a
/// Python docstring. The header is that comment (or docstring) and the comment lines right after it. A
/// documentation comment directly above a declaration other than an `import`, `package`, `#include`, or `using`
/// documents the declaration, not the file, so it doesn't count. With the `pattern` parameter (a regular
/// expression), the header must also contain a match. Empty files and unrecognized languages are skipped.
public struct MissingFileHeaderRule: Rule {
    public static let ruleID = "missing-file-header"
    public let id = MissingFileHeaderRule.ruleID
    private let profile: LanguageProfile
    private static let skippable = TextMatching.regex(
        #"^\s*$|^#!|^//\s*swift-tools-version|^//go:build|^//\s*\+build|^#.*-\*-.*coding|^["']use strict["'];?\s*$"#
    )
    private static let docstring = TextMatching.regex(#"^\s*[rRuUbB]?("""|''')"#)
    private static let fileLevelCode = TextMatching.regex(#"^\s*(import|package|#include|using|from|@file)\b"#)

    /// Creates the rule for one language.
    ///
    /// - Parameter profile: The language's profile, for its comment syntax.
    public init(profile: LanguageProfile) {
        self.profile = profile
    }

    /// Flags a file without a header, or with one that doesn't match `pattern`.
    ///
    /// Runs only when `.bouncer` enables it explicitly.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's `pattern` parameter.
    /// - Returns: One finding at line 1, or none.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        guard let settings = SourceText.optInSettings(id, context),
              let syntax = CommentSyntax(language: file.language, profile: profile),
              let first = file.lines.firstIndex(where: { !TextMatching.matches(Self.skippable, $0) }) else { return [] }
        let header = Self.header(in: file, from: first, syntax: syntax)
        let message = Self.problem(with: header, pattern: settings.parameters.string("pattern", default: ""))
        return message.map { [SourceText.finding(id, settings, file, header == nil ? 0 : first, $0)] } ?? []
    }

    /// Describes what's wrong with a file's header, if anything.
    ///
    /// - Parameters:
    ///   - header: The header's text, or `nil` if the file has none.
    ///   - pattern: The regular expression the header must contain a match for, or empty for none.
    /// - Returns: The finding's message, or `nil` if the header is fine.
    private static func problem(with header: String?, pattern: String) -> String? {
        guard let header else { return "File has no header comment." }
        guard !pattern.isEmpty, !TextMatching.matches(try? NSRegularExpression(pattern: pattern), header) else {
            return nil
        }
        return "File header doesn't match the required pattern."
    }

    /// Reads a file's header: the comment or docstring starting at a line, and the comment lines right after it.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - first: The 0-based first line after skipped ones.
    ///   - syntax: The file's comment syntax.
    /// - Returns: The header's text, or `nil` if the line doesn't start a file header.
    private static func header(in file: SourceFile, from first: Int, syntax: CommentSyntax) -> String? {
        if TextMatching.matches(docstring, file.lines[first]) { return docstringText(in: file, from: first) }
        let scanned = CommentScanner.scan(file, syntax: syntax)
        let run = scanned[first...].prefix { if case .comment = $0 { true } else { false } }
        guard case .comment(let opening)? = run.first else { return nil }
        let next = first + run.count
        guard !opening.isDoc || !documentsDeclaration(at: next, in: file) else { return nil }
        return file.lines[first..<next].joined(separator: "\n")
    }

    /// Reports whether a doc comment ending just above a line documents a declaration there, not the file.
    ///
    /// - Parameters:
    ///   - next: The 0-based line after the comment.
    ///   - file: The file.
    /// - Returns: Whether that line is code other than an `import`, `package`, `#include`, or `using`.
    private static func documentsDeclaration(at next: Int, in file: SourceFile) -> Bool {
        guard next < file.lines.count, !file.lines[next].allSatisfy(\.isWhitespace) else { return false }
        return !TextMatching.matches(fileLevelCode, file.lines[next])
    }

    /// Reads a Python module docstring, from its opening line to the line that closes it.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - first: The 0-based line the docstring opens on.
    /// - Returns: The docstring's text, quotes included.
    private static func docstringText(in file: SourceFile, from first: Int) -> String {
        let quote = file.lines[first].contains("'''") ? "'''" : "\"\"\""
        let opensAndCloses = file.lines[first].components(separatedBy: quote).count > 2
        let close = opensAndCloses ? first : file.lines.indices.dropFirst(first + 1).first {
            file.lines[$0].contains(quote)
        } ?? file.lines.count - 1
        return file.lines[first...close].joined(separator: "\n")
    }
}
