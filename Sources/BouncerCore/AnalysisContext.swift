import Foundation

/// The state a `Rule` or `LanguageAnalyzer` needs beyond the file itself.
///
/// Everything a rule might need that isn't the file's own content lives here,
/// so `Rule.evaluate` stays a pure function of `(SourceFile, AnalysisContext)`
/// and is trivial to unit test with a hand-built context.
public struct AnalysisContext: Sendable {
    /// The repository root, used by rules that report paths relative to it.
    public let repoRoot: URL

    /// Resolved settings for every rule, keyed by rule identifier.
    public let ruleSettings: [String: RuleSettings]

    /// Creates an analysis context.
    ///
    /// - Parameters:
    ///   - repoRoot: The repository root.
    ///   - ruleSettings: Resolved settings for every rule, keyed by rule identifier.
    public init(repoRoot: URL, ruleSettings: [String: RuleSettings]) {
        self.repoRoot = repoRoot
        self.ruleSettings = ruleSettings
    }

    /// Looks up a rule's settings, falling back to enabled-with-defaults.
    ///
    /// - Parameter ruleID: The rule's identifier.
    /// - Returns: The configured settings, or `RuleSettings.defaultEnabled`.
    public func settings(for ruleID: String) -> RuleSettings {
        ruleSettings[ruleID] ?? .defaultEnabled
    }
}
