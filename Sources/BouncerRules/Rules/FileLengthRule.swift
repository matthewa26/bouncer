import BouncerCore

/// Flags a file whose logical line count exceeds a configured maximum.
public struct FileLengthRule: Rule {
    public static let ruleID = "file-length"
    public let id = FileLengthRule.ruleID
    private let profile: LanguageProfile

    /// Creates the rule for a specific language's comment syntax.
    ///
    /// - Parameter profile: The language profile to count logical lines against.
    public init(profile: LanguageProfile) {
        self.profile = profile
    }

    /// Flags the file once if its logical line count exceeds `maxLines`.
    ///
    /// - Parameters:
    ///   - file: The file to measure.
    ///   - context: Repo-wide state, including this rule's `maxLines` parameter.
    /// - Returns: A single finding, or none.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled else { return [] }
        let maxLines = settings.parameters.int("maxLines", default: 500)
        let count = LogicalLineCounter.count(in: file, profile: profile)
        guard count > maxLines else { return [] }
        let message = "File has \(count) logical lines, over the \(maxLines)-line limit."
        return [Finding(ruleID: id, severity: settings.severity, filePath: file.path, line: 1, message: message)]
    }
}
