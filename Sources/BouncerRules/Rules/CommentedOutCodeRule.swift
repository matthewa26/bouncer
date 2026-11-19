import Foundation
import BouncerCore

/// Flags runs of comment lines that read as code someone commented out instead of deleting.
///
/// Doc comments, license headers, fenced or indented examples, and comments introduced by a `label:` line are
/// skipped; see `CodeLikeness` for how a line is scored.
public struct CommentedOutCodeRule: Rule {
    public static let ruleID = "commented-out-code"
    public let id = CommentedOutCodeRule.ruleID
    private let profile: LanguageProfile
    private static let licensePattern = try? NSRegularExpression(
        pattern: #"(?i)copyright|licen[cs]e|spdx|all rights reserved|\(c\)\s*\d{4}"#
    )

    /// Creates the rule for one language.
    ///
    /// - Parameter profile: The language's profile, for its comment syntax.
    public init(profile: LanguageProfile) {
        self.profile = profile
    }

    /// Flags each stretch of commented-out code, once, at its first line.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's `minLines` parameter.
    /// - Returns: One finding per stretch of commented-out code.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, let syntax = CommentSyntax(language: file.language, profile: profile) else { return [] }
        let minLines = max(1, settings.parameters.int("minLines", default: 2))
        return CommentScanner.runs(in: file, syntax: syntax)
            .filter { !$0.isDoc && !Self.isLicense($0) && !Self.isCgoPreamble($0, in: file) }
            .flatMap { CommentedCodeFinder.blocks(in: $0, minLines: minLines) }
            .map { finding(for: $0, file: file, severity: settings.severity) }
    }

    /// Builds the finding for one stretch of commented-out code.
    ///
    /// - Parameters:
    ///   - block: The stretch of commented-out code.
    ///   - file: The file it's in.
    ///   - severity: The severity to report at.
    /// - Returns: The finding, at the stretch's first line.
    private func finding(for block: CommentedCodeBlock, file: SourceFile, severity: Severity) -> Finding {
        let noun = block.codeLines == 1 ? "line" : "lines"
        let message = "Commented-out code (\(block.codeLines) \(noun)); delete it, version control keeps the history."
        return Finding(ruleID: id, severity: severity, filePath: file.path, line: block.firstLine + 1, message: message)
    }

    /// Reports whether a comment run is a Go cgo preamble: C code in the comment directly above `import "C"`.
    ///
    /// - Parameters:
    ///   - run: The comment run to check.
    ///   - file: The file it's in.
    /// - Returns: Whether the run is live C code that cgo compiles.
    private static func isCgoPreamble(_ run: CommentRun, in file: SourceFile) -> Bool {
        guard file.language == .go, let next = run.lines.last.map({ $0.index + 1 }), next < file.lines.count
        else { return false }
        return file.lines[next].trimmingCharacters(in: .whitespaces) == #"import "C""#
    }

    /// Reports whether a comment run is a license or copyright notice.
    ///
    /// - Parameter run: The comment run to check.
    /// - Returns: Whether any of its lines mentions a copyright, license, or SPDX identifier.
    private static func isLicense(_ run: CommentRun) -> Bool {
        run.lines.contains { line in
            let text = String(line.body)
            return licensePattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
    }
}

/// A stretch of adjacent comment lines that reads as code.
struct CommentedCodeBlock: Sendable {
    /// The 0-based index of the stretch's first code-like line.
    let firstLine: Int
    /// How many of its lines read as code (blank comment lines between them aren't counted).
    var codeLines: Int
    /// The highest `CodeLikeness` score among its lines.
    var maxScore: Double
    /// Whether the stretch is an example: fenced, indented under prose, or after a `label:` or `e.g.` line.
    let isExample: Bool

    /// Reports whether the stretch should be flagged.
    ///
    /// - Parameter minLines: The fewest code-like lines a stretch needs, unless one line is unambiguous code.
    /// - Returns: Whether it's long enough or strong enough, and not an example.
    func isReportable(minLines: Int) -> Bool {
        !isExample && (codeLines >= minLines || maxScore >= CodeLikeness.strongThreshold)
    }
}

/// Walks one comment run, splitting it into stretches of code-like lines separated by prose.
struct CommentedCodeFinder {
    private var blocks: [CommentedCodeBlock] = []
    private var current: CommentedCodeBlock?
    private var inFence = false
    private var labelAbove = false
    private var proseIndent: Int?
    private static let tabWidth = 4

    /// Finds the reportable stretches of code in a comment run.
    ///
    /// - Parameters:
    ///   - run: A non-doc comment run.
    ///   - minLines: The fewest code-like lines a stretch needs, unless one line is unambiguous code.
    /// - Returns: The stretches to flag.
    static func blocks(in run: CommentRun, minLines: Int) -> [CommentedCodeBlock] {
        var finder = CommentedCodeFinder()
        run.lines.forEach { finder.feed($0) }
        finder.close()
        return finder.blocks.filter { $0.isReportable(minLines: minLines) }
    }

    /// Feeds one comment line: extends the current stretch if it reads as code, otherwise ends it.
    ///
    /// A line needs `codeThreshold` to start a stretch but only `continuationThreshold` to extend one.
    ///
    /// - Parameter line: The next comment line in the run.
    private mutating func feed(_ line: CommentLine) {
        let text = line.body.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let score = score(text, body: line.body)
        let threshold = current == nil ? CodeLikeness.codeThreshold : CodeLikeness.continuationThreshold
        guard score < threshold else { return extend(line, score: score) }
        close()
        labelAbove = labelAbove || text.hasSuffix(":") || Self.namesExample(text)
        proseIndent = Self.indent(of: line.body)
    }

    /// Scores one comment line, tracking Markdown code fences: a fence line and everything inside one is prose.
    ///
    /// - Parameters:
    ///   - text: The trimmed comment text.
    ///   - body: The untrimmed text after the comment marker.
    /// - Returns: The line's `CodeLikeness` score, or `-.infinity` for fenced lines and example announcements.
    private mutating func score(_ text: String, body: Substring) -> Double {
        let isFence = text.hasPrefix("```") || text.hasPrefix("~~~")
        if isFence { inFence.toggle() }
        return inFence || isFence || Self.namesExample(text) ? -.infinity : CodeLikeness.score(body)
    }

    /// Adds a code-like line to the current stretch, starting one if needed.
    ///
    /// - Parameters:
    ///   - line: The code-like comment line.
    ///   - score: Its `CodeLikeness` score.
    private mutating func extend(_ line: CommentLine, score: Double) {
        guard var block = current else {
            let indented = proseIndent.map { Self.indent(of: line.body) > $0 + 1 } ?? false
            current = CommentedCodeBlock(firstLine: line.index, codeLines: 1, maxScore: score,
                                         isExample: labelAbove || indented)
            return
        }
        block.codeLines += 1
        block.maxScore = max(block.maxScore, score)
        current = block
    }

    /// Ends the current stretch, if any, keeping it as a candidate.
    private mutating func close() {
        if let block = current { blocks.append(block) }
        current = nil
    }

    /// Reports whether a line ends by announcing an example, such as `For example:` or `..., e.g.`.
    ///
    /// Such a line is always prose, and (like any prose line ending in a colon) marks the rest of its comment run as
    /// an example.
    ///
    /// - Parameter text: The trimmed comment text.
    /// - Returns: Whether it ends with `e.g.`, `i.e.`, `for example`, `for instance`, `such as`, `example`, or `usage`.
    private static func namesExample(_ text: String) -> Bool {
        let lowered = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":,"))
        return ["e.g.", "i.e.", "for example", "for instance", "such as", "example", "usage"]
            .contains { lowered.hasSuffix($0) }
    }

    /// Measures a comment body's indentation after its comment marker.
    ///
    /// - Parameter body: The text after the comment marker.
    /// - Returns: The number of leading spaces, counting a tab as four.
    private static func indent(of body: Substring) -> Int {
        body.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? tabWidth : 1) }
    }
}
