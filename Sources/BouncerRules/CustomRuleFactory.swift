import BouncerCore

/// Builds `Rule`s from user-declared `customRules` in `.bouncer`.
///
/// Every custom rule in v1 is a `PatternRule` - declarative regex matching,
/// not arbitrary code - so a repo can add its own checks without writing
/// Swift.
public enum CustomRuleFactory {
    /// Builds one rule per valid specification, silently dropping any with an invalid pattern.
    ///
    /// - Parameter specs: The custom rule specifications from `.bouncer`.
    /// - Returns: The constructed rules.
    public static func makeRules(from specs: [PatternRuleSpec]) -> [Rule] {
        specs.compactMap(PatternRule.init)
    }
}
