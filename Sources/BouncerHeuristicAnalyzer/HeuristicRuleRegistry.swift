import BouncerCore
import BouncerRules

/// Builds the 13 shared heuristic rules, plus any language-specific extras, for one language.
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
        return sharedRules(profile: profile) + CustomRuleFactory.makeRules(from: profile.extraPatternRules)
    }

    /// Builds the 13 rules shared across every heuristically-analyzed language.
    ///
    /// - Parameter profile: The language's profile.
    /// - Returns: The 13 shared rules, each bound to `profile`.
    private func sharedRules(profile: LanguageProfile) -> [Rule] {
        smellRules(profile: profile) + qualityRules(profile: profile)
    }

    /// Builds the 8 general code-smell rules every heuristically-analyzed language shares.
    ///
    /// - Parameter profile: The language's profile.
    /// - Returns: The 8 smell rules, each bound to `profile`.
    private func smellRules(profile: LanguageProfile) -> [Rule] {
        [
            FileLengthRule(profile: profile), LongFunctionRule(profile: profile), DeepNestingRule(), LongLineRule(),
            TodoDensityRule(), DuplicateBlockRule(), TrailingWhitespaceRule(), SecretPatternRule()
        ]
    }

    /// Builds the 5 CSE-3902-derived code-quality rules every language shares.
    ///
    /// - Parameter profile: The language's profile.
    /// - Returns: The 5 quality rules, each bound to `profile`.
    private func qualityRules(profile: LanguageProfile) -> [Rule] {
        [
            CyclomaticComplexityRule(profile: profile), NamingConventionRule(profile: profile),
            HighCouplingRule(profile: profile), SwitchOnTypeSmellRule(profile: profile),
            MissingDocumentationRule(profile: profile)
        ]
    }
}
