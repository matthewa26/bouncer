import Foundation
import BouncerCore

/// Flags a function whose branch count exceeds a configured maximum.
///
/// A heuristic stand-in for McCabe complexity: counts branch-introducing
/// keywords and operators within each function block found by
/// `BlockSegmenter`, plus one. `BouncerSwiftAnalyzer` computes this exactly
/// from the syntax tree instead.
public struct CyclomaticComplexityRule: Rule {
    public static let ruleID = "cyclomatic-complexity"
    public let id = CyclomaticComplexityRule.ruleID
    private static let branchPattern = try? NSRegularExpression(
        pattern: "\\b(if|else if|elif|case|when|for|while|catch|except|and|or)\\b|&&|\\|\\|"
    )
    private let profile: LanguageProfile

    /// Creates the rule for a specific language's function syntax.
    ///
    /// - Parameter profile: The language profile providing the function-start pattern.
    public init(profile: LanguageProfile) {
        self.profile = profile
    }

    /// Flags every function whose branch count exceeds `max`.
    ///
    /// - Parameters:
    ///   - file: The file to scan for functions.
    ///   - context: Repo-wide state, including this rule's `max` parameter.
    /// - Returns: One finding per over-complex function.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, let pattern = profile.functionStartPattern else { return [] }
        guard let regex = Self.branchPattern else { return [] }
        let max = settings.parameters.int("max", default: 10)
        return BlockSegmenter.blocks(in: file, startPattern: pattern).compactMap {
            finding(for: $0, in: file, regex: regex, max: max, severity: settings.severity)
        }
    }

    /// Builds a finding for one function block if its complexity exceeds `max`.
    ///
    /// - Parameters:
    ///   - block: The function's line span.
    ///   - file: The file the function belongs to.
    ///   - regex: The compiled branch-keyword pattern.
    ///   - max: The configured maximum complexity.
    ///   - severity: The severity to report at.
    /// - Returns: A finding, or `nil` if within the limit.
    private func finding(
        for block: LineBlock, in file: SourceFile, regex: NSRegularExpression, max: Int, severity: Severity
    ) -> Finding? {
        let complexity = 1 + branchCount(in: block, file: file, regex: regex)
        guard complexity > max else { return nil }
        let message = "Function has an estimated cyclomatic complexity of \(complexity), over the \(max) limit."
        return Finding(ruleID: id, severity: severity, filePath: file.path, line: block.startLine + 1, message: message)
    }

    /// Counts branch-keyword matches across a block's lines.
    ///
    /// - Parameters:
    ///   - block: The block's line span.
    ///   - file: The file the block belongs to.
    ///   - regex: The compiled branch-keyword pattern.
    /// - Returns: The total number of matches.
    private func branchCount(in block: LineBlock, file: SourceFile, regex: NSRegularExpression) -> Int {
        (block.startLine...block.endLine).reduce(0) { total, index in
            let text = String(file.lines[index])
            return total + regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        }
    }
}
