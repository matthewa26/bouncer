import BouncerCore
import BouncerRules

/// Builds the heuristic rules for one language: the shared text-level rules, plus heuristic
/// approximations of the rules parser-backed analyzers compute from a syntax tree.
public struct HeuristicRuleRegistry: RuleRegistry {
    /// Creates the registry. It has no state of its own; everything comes from the language profile.
    public init() {}

    /// Builds every heuristic rule that applies to a language.
    ///
    /// - Parameters:
    ///   - language: The language being analyzed.
    ///   - ruleSettings: Resolved settings for every rule, keyed by identifier. Unused here —
    ///     each `Rule` reads its own settings from the `AnalysisContext` at evaluation time.
    /// - Returns: The rules to run, in a fixed order.
    public func rules(for language: Language, ruleSettings: [String: RuleSettings]) -> [Rule] {
        let profile = LanguageProfiles.profile(for: language)
        return TextRules.make(profile: profile) + structureRules(profile: profile)
    }

    /// Builds the indentation- and regex-based stand-ins for the syntax-tree rules.
    ///
    /// - Parameter profile: The language's profile.
    /// - Returns: The heuristic structure rules, each bound to `profile`.
    private func structureRules(profile: LanguageProfile) -> [Rule] {
        [
            LongFunctionRule(profile: profile), CyclomaticComplexityRule(profile: profile),
            NamingConventionRule(profile: profile), HighCouplingRule(profile: profile),
            SwitchOnTypeSmellRule(profile: profile), MissingDocumentationRule(profile: profile)
        ]
    }
}
