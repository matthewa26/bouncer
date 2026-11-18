import BouncerCore

/// Flags a line ending in trailing whitespace.
public struct TrailingWhitespaceRule: Rule {
    public static let ruleID = "trailing-whitespace"
    public let id = TrailingWhitespaceRule.ruleID

    /// Creates the rule. Trailing whitespace is language-agnostic, so no profile is needed.
    public init() {}

    /// Flags every non-blank line ending in a space or tab.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per line with trailing whitespace.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled else { return [] }
        return file.lines.enumerated().compactMap { index, line in
            finding(forLine: line, index: index, file: file, severity: settings.severity)
        }
    }

    /// Builds a finding for one line if it ends in a space or tab.
    ///
    /// - Parameters:
    ///   - line: The line's text.
    ///   - index: The line's 0-indexed position.
    ///   - file: The file being analyzed.
    ///   - severity: The severity to report at.
    /// - Returns: A finding, or `nil` if the line has no trailing whitespace.
    private func finding(forLine line: Substring, index: Int, file: SourceFile, severity: Severity) -> Finding? {
        guard let last = line.last, last == " " || last == "\t" else { return nil }
        let message = "Line has trailing whitespace."
        return Finding(ruleID: id, severity: severity, filePath: file.path, line: index + 1, message: message)
    }
}
