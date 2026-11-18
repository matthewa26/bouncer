import BouncerCore

/// Flags a line nested deeper than a configured maximum indentation depth.
public struct DeepNestingRule: Rule {
    public static let ruleID = "deep-nesting"
    public let id = DeepNestingRule.ruleID

    /// Creates the rule. Nesting depth is language-agnostic, so no profile is needed.
    public init() {}

    /// Flags every line whose indentation depth exceeds the configured maximum.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's `maxDepth` parameter.
    /// - Returns: One finding per over-nested line.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled else { return [] }
        let params = NestingParams(settings: settings)
        return file.lines.enumerated().compactMap { finding(forLine: $1, index: $0, file: file, params: params) }
    }

    /// This rule's tunable thresholds, bundled to keep call sites short.
    private struct NestingParams {
        let maxDepth: Int
        let indentWidth: Int
        let severity: Severity

        /// Reads this rule's thresholds out of its resolved settings.
        ///
        /// - Parameter settings: The rule's resolved settings.
        init(settings: RuleSettings) {
            maxDepth = settings.parameters.int("maxDepth", default: 16)
            indentWidth = settings.parameters.int("indentWidth", default: 4)
            severity = settings.severity
        }
    }

    /// Builds a finding for one line if it's indented past `maxDepth`.
    ///
    /// - Parameters:
    ///   - line: The line's text.
    ///   - index: The line's 0-indexed position.
    ///   - file: The file being analyzed.
    ///   - params: This rule's tunable thresholds.
    /// - Returns: A finding, or `nil` if within the limit.
    private func finding(forLine line: Substring, index: Int, file: SourceFile, params: NestingParams) -> Finding? {
        guard !LineClassifier.isBlank(line) else { return nil }
        let depth = Indentation.depth(of: line) / max(params.indentWidth, 1)
        guard depth > params.maxDepth else { return nil }
        let message = "Line is nested \(depth) levels deep, over the \(params.maxDepth)-level limit."
        return Finding(ruleID: id, severity: params.severity, filePath: file.path, line: index + 1, message: message)
    }
}
