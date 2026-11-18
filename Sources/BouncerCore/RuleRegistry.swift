/// Builds the set of rules that should run against a given language.
///
/// Rules are constructed here, from `RuleSettings`, rather than being a fixed
/// list - this is the seam that makes every rule individually enabled,
/// disabled, and parameterized per repo.
public protocol RuleRegistry: Sendable {
    /// Returns the rules that apply to a language, built from resolved settings.
    ///
    /// - Parameters:
    ///   - language: The language being analyzed.
    ///   - ruleSettings: Resolved settings for every rule, keyed by identifier.
    /// - Returns: The rules to run, already configured and ready to evaluate.
    func rules(for language: Language, ruleSettings: [String: RuleSettings]) -> [Rule]
}
