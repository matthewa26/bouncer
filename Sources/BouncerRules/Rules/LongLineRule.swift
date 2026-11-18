import BouncerCore

/// Flags a line longer than a configured maximum character count.
public struct LongLineRule: Rule {
    public static let ruleID = "long-lines"
    public let id = LongLineRule.ruleID

    /// Creates the rule. Line length is language-agnostic, so no profile is needed.
    public init() {}

    /// Flags every line longer than the configured maximum.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's `maxLength` parameter.
    /// - Returns: One finding per over-long line.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled else { return [] }
        let maxLength = settings.parameters.int("maxLength", default: 120)
        return file.lines.enumerated().compactMap { index, line in
            finding(forLine: line, index: index, file: file, maxLength: maxLength, severity: settings.severity)
        }
    }

    /// Builds a finding for one line if it exceeds `maxLength`.
    ///
    /// - Parameters:
    ///   - line: The line's text.
    ///   - index: The line's 0-indexed position.
    ///   - file: The file being analyzed.
    ///   - maxLength: The configured maximum character count.
    ///   - severity: The severity to report at.
    /// - Returns: A finding, or `nil` if within the limit.
    private func finding(
        forLine line: Substring, index: Int, file: SourceFile, maxLength: Int, severity: Severity
    ) -> Finding? {
        guard line.count > maxLength else { return nil }
        let message = "Line is \(line.count) characters, over the \(maxLength)-character limit."
        return Finding(ruleID: id, severity: severity, filePath: file.path, line: index + 1, message: message)
    }
}
