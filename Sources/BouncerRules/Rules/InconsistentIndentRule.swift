import BouncerCore

/// Flags a file whose blocks aren't all indented by the same number of spaces, such as one block indented by 2 in
/// a file that otherwise indents by 4.
///
/// It measures only block steps: the indentation of the first code line inside a block, relative to the line that
/// opens it (ending in `{`, Python's `:`, or a shell `then`/`do`/`else`). A block opened on a continuation line (one
/// after a trailing comma, operator, or open bracket, one starting with a closing bracket or operator, or one leaving
/// a bracket open, as in `items.map({`) isn't measured, since its indentation is alignment. Comments, the contents
/// of multi-line strings and template literals, and tab-indented lines (left to `mixed-indentation`) never count.
/// The most common step is taken as the file's width, and the rule reports once per file, at the first block that
/// differs, only when that width has at least two blocks and more than every other width combined. Go (gofmt
/// aligns with spaces inside tab indentation) and SQL (free-form) aren't checked.
public struct InconsistentIndentRule: Rule {
    public static let ruleID = "inconsistent-indent"
    public let id = InconsistentIndentRule.ruleID
    private let profile: LanguageProfile

    /// Creates the rule for one language.
    ///
    /// - Parameter profile: The language's profile, for its comment syntax.
    public init(profile: LanguageProfile) {
        self.profile = profile
    }

    /// Flags the file's first block whose indentation step differs from its usual width.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: A single finding, or none.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, file.language != .go, file.language != .sql,
              let syntax = CommentSyntax(language: file.language, profile: profile) else { return [] }
        let steps = BlockSteps(file: file, syntax: syntax).steps()
        guard let width = Self.usualWidth(of: steps) else { return [] }
        guard let first = steps.first(where: { $0.width != width }) else { return [] }
        let message = Self.message(first: first, differing: steps.filter { $0.width != width }.count, width: width)
        return [Finding(ruleID: id, severity: settings.severity, filePath: file.path, line: first.line + 1,
                        message: message)]
    }

    /// Describes the file's indentation mismatch.
    ///
    /// - Parameters:
    ///   - first: The first block that differs.
    ///   - differing: How many blocks differ.
    ///   - width: The file's usual width.
    /// - Returns: The finding's message.
    private static func message(first: BlockStep, differing: Int, width: Int) -> String {
        let spaces = first.width == 1 ? "1 space" : "\(first.width) spaces"
        let blocks = differing == 1 ? "1 block differs" : "\(differing) blocks differ"
        return "Block indented by \(spaces); the rest of this file indents by \(width) (\(blocks))."
    }

    /// Picks the file's indentation width: the most common block step, if it's clearly the norm.
    ///
    /// - Parameter steps: Every block step in the file.
    /// - Returns: The width, or `nil` if it has fewer than two blocks or no more than every other width combined.
    private static func usualWidth(of steps: [BlockStep]) -> Int? {
        let counts = Dictionary(grouping: steps, by: \.width).mapValues(\.count)
        guard let (width, count) = counts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }),
              count >= 2, count > steps.count - count else { return nil }
        return width
    }
}

/// One block's indentation step: how far its first line is indented past the statement that opens it.
struct BlockStep: Sendable {
    /// The 0-based index of the block's first code line.
    let line: Int
    /// The number of spaces it's indented past its opening statement.
    let width: Int
}

/// Finds every block step in a file, skipping comments, multi-line string contents, and continuation lines.
struct BlockSteps {
    private let file: SourceFile
    private let isCode: [Bool]
    private let openers: [String]
    private let continuationEndings = [",", "(", "[", "&&", "||", "+", "-", "*", "/", "=", "?", "\\", "|", " and",
                                       " or"]
    private let continuationStarts = [")", "]", ".", "&&", "||", "?", ":", "+", "-", "*", "|", ">", "where "]

    /// Prepares a file for scanning.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - syntax: Its comment syntax.
    init(file: SourceFile, syntax: CommentSyntax) {
        self.file = file
        let interior = MultilineStringMask.interiorLines(of: file)
        self.isCode = CommentScanner.scan(file, syntax: syntax).enumerated().map { index, kind in
            if case .code = kind { return !interior[index] }
            return false
        }
        self.openers = Self.openers(for: file.language)
    }

    /// Lists the tokens that end a block-opening line in a language.
    ///
    /// - Parameter language: The file's language.
    /// - Returns: The line endings that open a block.
    private static func openers(for language: Language) -> [String] {
        switch language {
        case .python: return [":"]
        case .bash, .zsh: return ["{", " then", " do", "else"]
        default: return ["{"]
        }
    }

    /// Measures every block step in the file.
    ///
    /// - Returns: The steps, in file order; only positive, space-indented steps are included.
    func steps() -> [BlockStep] {
        file.lines.indices.compactMap { index in
            guard isCode[index], opensBlock(file.lines[index]), !isContinuation(index),
                  let body = nextCodeLine(after: index), let outer = spaceIndent(file.lines[index]),
                  let inner = spaceIndent(file.lines[body]), inner > outer else { return nil }
            return BlockStep(line: body, width: inner - outer)
        }
    }

    /// Reports whether a code line ends by opening a block.
    ///
    /// - Parameter line: The line to check.
    /// - Returns: Whether its last token is one of the language's block openers.
    private func opensBlock(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return openers.contains { trimmed.hasSuffix($0) && (trimmed.count > $0.count || $0 != "else") }
    }

    /// Finds the first code line of the block a line opens.
    ///
    /// - Parameter index: The opening line's 0-based index.
    /// - Returns: The next code line's index, or `nil` if the block is empty or a non-code line interrupts it.
    private func nextCodeLine(after index: Int) -> Int? {
        var next = index + 1
        while next < file.lines.count, LineClassifier.isBlank(file.lines[next]) { next += 1 }
        guard next < file.lines.count, isCode[next] else { return nil }
        let first = file.lines[next].drop(while: \.isWhitespace).first
        return first.map { "})]".contains($0) } == true ? nil : next
    }

    /// Reports whether a line continues the statement above it, by that line's trailing operator, comma, or open
    /// bracket, or by its own leading closing bracket or operator; such a line's indentation is alignment, not a
    /// block level, so blocks it opens aren't measured. A block opened inside a bracket the line leaves open, as in
    /// `items.map({`, counts too, since formatters may indent its body as a continuation.
    ///
    /// - Parameter index: The line's 0-based index.
    /// - Returns: Whether the line is a continuation line.
    private func isContinuation(_ index: Int) -> Bool {
        let line = file.lines[index].drop(while: \.isWhitespace)
        if continuationStarts.contains(where: { line.hasPrefix($0) }) { return true }
        let opened = line.filter { $0 == "(" || $0 == "[" }.count, closed = line.filter { $0 == ")" || $0 == "]" }.count
        if opened > closed { return true }
        guard index > 0, isCode[index - 1] else { return false }
        let before = file.lines[index - 1].trimmingCharacters(in: .whitespaces)
        return continuationEndings.contains { before.hasSuffix($0) }
    }

    /// Measures a line's indentation if it's made of spaces only.
    ///
    /// - Parameter line: The line to measure.
    /// - Returns: The number of leading spaces, or `nil` if the indentation contains a tab.
    private func spaceIndent(_ line: Substring) -> Int? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        return indent.contains("\t") ? nil : indent.count
    }
}
