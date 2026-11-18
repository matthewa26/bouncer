import Foundation

/// One reported violation of a rule.
public struct Finding: Sendable, Equatable {
    /// The identifier of the rule that produced this finding, such as `"long-function"`.
    public let ruleID: String

    /// The severity this finding was reported at.
    public let severity: Severity

    /// The file the finding applies to.
    public let filePath: URL

    /// The 1-indexed line the finding points to.
    public let line: Int

    /// A human-readable explanation of the violation.
    public let message: String

    /// Creates a finding.
    ///
    /// - Parameters:
    ///   - ruleID: The identifier of the rule that produced this finding.
    ///   - severity: The severity this finding was reported at.
    ///   - filePath: The file the finding applies to.
    ///   - line: The 1-indexed line the finding points to.
    ///   - message: A human-readable explanation of the violation.
    public init(ruleID: String, severity: Severity, filePath: URL, line: Int, message: String) {
        self.ruleID = ruleID
        self.severity = severity
        self.filePath = filePath
        self.line = line
        self.message = message
    }
}
