import BouncerCore

/// Flags a switch-like statement with more branches than a configured threshold.
///
/// A long branch on a type tag is a well-established proxy for "this should
/// probably be polymorphism, Strategy, or State" - this rule flags the
/// symptom; it can't verify that a better structure actually exists.
public struct SwitchOnTypeSmellRule: Rule {
    public static let ruleID = "switch-on-type-smell"
    public let id = SwitchOnTypeSmellRule.ruleID
    private let profile: LanguageProfile

    /// Creates the rule for a specific language's switch syntax.
    ///
    /// - Parameter profile: The language profile providing the switch-block patterns.
    public init(profile: LanguageProfile) {
        self.profile = profile
    }

    /// Flags every switch block whose branch count exceeds `maxBranches`.
    ///
    /// - Parameters:
    ///   - file: The file to scan for switch statements.
    ///   - context: Repo-wide state, including this rule's `maxBranches` parameter.
    /// - Returns: One finding per over-large switch statement.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, let startPattern = profile.switchStartPattern,
              let branchPattern = profile.switchBranchPattern else { return [] }
        let maxBranches = settings.parameters.int("maxBranches", default: 6)
        return BlockSegmenter.blocks(in: file, startPattern: startPattern).compactMap {
            finding(
                for: $0, in: file, branchPattern: branchPattern, maxBranches: maxBranches, severity: settings.severity
            )
        }
    }

    /// Builds a finding for one switch block if its branch count exceeds `maxBranches`.
    ///
    /// - Parameters:
    ///   - block: The switch statement's line span.
    ///   - file: The file the switch belongs to.
    ///   - branchPattern: The regex matching one branch line.
    ///   - maxBranches: The configured maximum branch count.
    ///   - severity: The severity to report at.
    /// - Returns: A finding, or `nil` if within the limit.
    private func finding(
        for block: LineBlock, in file: SourceFile, branchPattern: String, maxBranches: Int, severity: Severity
    ) -> Finding? {
        let branchCount = BlockSegmenter.blocks(in: file, startPattern: branchPattern)
            .filter { $0.startLine >= block.startLine && $0.startLine <= block.endLine }
            .count
        guard branchCount > maxBranches else { return nil }
        let message = "Switch has \(branchCount) branches, over the \(maxBranches)-branch smell threshold."
        return Finding(ruleID: id, severity: severity, filePath: file.path, line: block.startLine + 1, message: message)
    }
}
