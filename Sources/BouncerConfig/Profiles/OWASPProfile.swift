import BouncerCore

/// The `owasp` bundled preset: every rule mapped to an OWASP Top 10:2025 category, enabled and reported as an
/// error, so a security review fails on any security finding. Rules that are off unless configured are turned
/// on too. Every other rule keeps its default, and config layers applied on top can still override any of these.
public enum OWASPProfile {
    /// This preset's config, applied as the base layer beneath `~/.bouncer` and a repo's `.bouncer`.
    public static let config = BouncerConfig(
        rules: Dictionary(uniqueKeysWithValues: OWASPCategory.mappedRuleIDs.map { ruleID in
            (ruleID, RuleConfigEntry(enabled: true, severity: .error))
        })
    )
}
