import BouncerCore

/// Flags a function whose logical line count exceeds a configured maximum.
///
/// Function boundaries are found heuristically via `BlockSegmenter`, using
/// each language profile's `functionStartPattern` and indentation
/// return-to-base to mark where the function ends.
public struct LongFunctionRule: Rule {
    public static let ruleID = "long-function"
    public let id = LongFunctionRule.ruleID
    private let profile: LanguageProfile

    /// Creates the rule for a specific language's function syntax.
    ///
    /// - Parameter profile: The language profile providing the function-start pattern.
    public init(profile: LanguageProfile) {
        self.profile = profile
    }

    /// Flags every function whose logical line count exceeds `maxLines`.
    ///
    /// - Parameters:
    ///   - file: The file to scan for functions.
    ///   - context: Repo-wide state, including this rule's `maxLines` parameter.
    /// - Returns: One finding per over-long function.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, let pattern = profile.functionStartPattern else { return [] }
        let maxLines = settings.parameters.int("maxLines", default: 40)
        return BlockSegmenter.blocks(in: file, startPattern: pattern).compactMap {
            finding(for: $0, in: file, maxLines: maxLines, severity: settings.severity)
        }
    }

    /// Builds a finding for one function block if it exceeds `maxLines`.
    ///
    /// - Parameters:
    ///   - block: The function's line span.
    ///   - file: The file the function belongs to.
    ///   - maxLines: The configured maximum logical line count.
    ///   - severity: The severity to report at.
    /// - Returns: A finding, or `nil` if the function is within the limit.
    private func finding(for block: LineBlock, in file: SourceFile, maxLines: Int, severity: Severity) -> Finding? {
        let count = LogicalLineCounter.count(in: file, range: block.startLine...block.endLine, profile: profile)
        guard count > maxLines else { return nil }
        let message = "Function has \(count) logical lines, over the \(maxLines)-line limit."
        return Finding(ruleID: id, severity: severity, filePath: file.path, line: block.startLine + 1, message: message)
    }
}
