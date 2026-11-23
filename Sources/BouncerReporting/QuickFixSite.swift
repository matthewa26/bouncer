import Foundation
import BouncerCore

/// A finding's place in its file, for a fixer: the reported line, its neighbours, and the file's language.
struct FixSite: Sendable {
    /// The finding being fixed.
    let finding: Finding
    /// The file's lines.
    let lines: [String]
    /// The reported line's 0-based index.
    let index: Int

    /// A previous line that leaves the next statement unbraced (`if (x)`, `else`, `=>`) or mid-expression (`(`, `,`,
    /// an operator), so deleting that next line would change what the code means.
    private static let unbracedHeader = TextPattern(
        #"^(\}\s*)?(else\s+)?(if|elseif|for|foreach|while)\b.*\)$|^(\}\s*)?else$|^do$|=>$|[(\[,=+\-*/%&|?.]$"#
    )

    /// Creates a site for a finding, if its line is in the file.
    ///
    /// - Parameters:
    ///   - finding: The finding.
    ///   - lines: Its file's lines.
    init?(finding: Finding, lines: [String]) {
        guard finding.line >= 1, finding.line <= lines.count else { return nil }
        self.finding = finding
        self.lines = lines
        self.index = finding.line - 1
    }

    /// The reported line's text.
    var text: String {
        lines[index]
    }

    /// The file's language, from its extension.
    var language: Language {
        Language.from(fileExtension: finding.filePath.pathExtension)
    }

    /// The reported line with its strings and trailing comment blanked, or `nil` when a string runs past its end.
    var code: MaskedLine? {
        MaskedLine(text, language: language)
    }

    /// The edit replacing the reported line with another.
    ///
    /// - Parameter replacement: The new line.
    /// - Returns: The edit, or `nil` when the replacement is the same line.
    func replacingLine(with replacement: String) -> QuickFix? {
        replacement == text ? nil : QuickFix(startLine: index + 1, removed: [text], added: [replacement])
    }

    /// The edit deleting the reported line, when that leaves the surrounding code meaning the same.
    ///
    /// - Returns: The edit, or `nil` when the line is an unbraced body, a block's only statement after a `:`, or part
    ///   of a longer expression.
    func removingLine() -> QuickFix? {
        guard canRemoveLine else { return nil }
        return QuickFix(startLine: index + 1, removed: [text], added: [])
    }

    /// Whether deleting the reported line keeps the code around it well formed.
    private var canRemoveLine: Bool {
        let previous = neighbour(step: -1), next = neighbour(step: 1)
        if let previous, Self.unbracedHeader.matches(previous.trimmed) { return false }
        if let next, let first = next.trimmed.first, ".?+-*/&|:".contains(first) { return false }
        guard let previous, previous.trimmed.hasSuffix(":") else { return true }
        return next.map { Self.indent(of: $0) == Self.indent(of: text) } ?? false
    }

    /// The nearest non-blank line before or after the reported one.
    ///
    /// - Parameter step: `-1` to look up, `1` to look down.
    /// - Returns: The line, or `nil` at the edge of the file.
    func neighbour(step: Int) -> String? {
        let candidates = stride(from: index + step, to: step < 0 ? -1 : lines.count, by: step)
        return candidates.lazy.map { lines[$0] }.first { !$0.trimmed.isEmpty }
    }

    /// The leading whitespace of a line.
    ///
    /// - Parameter line: The line.
    /// - Returns: Its indentation.
    static func indent(of line: String) -> Substring {
        line.prefix { $0 == " " || $0 == "\t" }
    }
}

extension String {
    /// The string without leading or trailing whitespace.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
