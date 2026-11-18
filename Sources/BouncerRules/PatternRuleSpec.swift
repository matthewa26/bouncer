/// Declares a regex-based rule as data, without writing a new `Rule` type.
///
/// Used both for a `LanguageProfile`'s extra per-language checks and for
/// `customRules` declared in `.bouncer` - both go through `PatternRule`.
public struct PatternRuleSpec: Sendable {
    /// The rule's stable identifier.
    public let id: String

    /// The regular expression a matching line must contain.
    public let pattern: String

    /// The message shown for a match.
    public let message: String

    /// Creates a pattern rule specification.
    ///
    /// - Parameters:
    ///   - id: The rule's stable identifier.
    ///   - pattern: The regular expression a matching line must contain.
    ///   - message: The message shown for a match.
    public init(id: String, pattern: String, message: String) {
        self.id = id
        self.pattern = pattern
        self.message = message
    }
}
