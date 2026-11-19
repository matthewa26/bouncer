import Foundation
import BouncerCore

/// Flags an empty `catch` block in the languages without a syntax tree: Java, C++, PowerShell, and unrecognized
/// languages with `try`/`catch` (C#, Kotlin, PHP, Dart). Swift, TypeScript, JavaScript, Python, and Go get the
/// parse-tree version of the same `empty-catch` rule instead.
///
/// It's text-based: a `catch` on a code line, optionally followed by its `(…)` or `[Type]` clause, opens a brace
/// block that's followed (across lines, up to 20) to its matching `}`. The block is empty when nothing but whitespace
/// lies between the braces; a comment inside counts as a deliberate "nothing to do here", as it does for the
/// parse-tree rule.
public struct EmptyCatchTextRule: Rule {
    public static let ruleID = "empty-catch"
    public let id = EmptyCatchTextRule.ruleID
    private static let catchOpen = TextMatching.regex(#"\bcatch\b\s*(?:\([^)]*\)|(?:\[[\w.]+\]\s*,?\s*)*)\s*\{"#)
    private static let maxBlockLines = 20

    /// Creates the rule.
    public init() {}

    /// Flags each empty `catch` block.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per empty block, at its `catch` line.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, Self.isTextOnlyLanguage(file.language), file.contents.contains("catch") else {
            return []
        }
        return SourceText.flagCodeLines(id, settings, file) { index in
            Self.opensEmptyCatch(at: index, in: file) ? "Empty catch block silently swallows the error." : nil
        }
    }

    /// Reports whether a language lacks the parse-tree `empty-catch`, so this text version should run.
    ///
    /// - Parameter language: The file's language.
    /// - Returns: Whether the language is Java, C++, PowerShell, or unrecognized.
    private static func isTextOnlyLanguage(_ language: Language) -> Bool {
        switch language {
        case .java, .cpp, .powershell, .other: true
        default: false
        }
    }

    /// Reports whether a line opens a `catch` block with nothing inside it.
    ///
    /// - Parameters:
    ///   - index: The line's 0-based index.
    ///   - file: The file it's in.
    /// - Returns: Whether the block after the `catch` is empty.
    private static func opensEmptyCatch(at index: Int, in file: SourceFile) -> Bool {
        let line = SourceText.blankingStrings(file.lines[index])
        guard let match = TextMatching.captures(catchOpen, line).first,
              let open = line.range(of: match[0]) else { return false }
        let rest = file.lines[(index + 1)..<min(file.lines.count, index + maxBlockLines)].map(String.init)
        return body(after: [String(line[open.upperBound...])] + rest)?.allSatisfy(\.isWhitespace) ?? false
    }

    /// Collects a block's text up to its matching `}`.
    ///
    /// - Parameter lines: The text after the opening `{`, then the following lines.
    /// - Returns: The block's contents, or `nil` if it doesn't close within the lines given.
    private static func body(after lines: [String]) -> String? {
        var depth = 1
        let text = lines.map(SourceText.blankingStrings).joined(separator: "\n")
        let end = text.firstIndex { char in
            if char == "{" { depth += 1 } else if char == "}" { depth -= 1 }
            return depth == 0
        }
        return end.map { String(text[..<$0]) }
    }
}
