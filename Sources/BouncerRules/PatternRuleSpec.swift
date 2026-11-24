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

    /// A regular expression that, matched anywhere in a file (`^` and `$` match at each line), exempts the whole
    /// file, such as a Python script's `__main__` guard for `python-debug-print`.
    public let exemptFilePattern: String?

    /// Creates a pattern rule specification.
    ///
    /// - Parameters:
    ///   - id: The rule's stable identifier.
    ///   - pattern: The regular expression a matching line must contain.
    ///   - message: The message shown for a match.
    ///   - exemptFilePattern: A regular expression that exempts any file it matches, or `nil`.
    public init(id: String, pattern: String, message: String, exemptFilePattern: String? = nil) {
        self.id = id
        self.pattern = pattern
        self.message = message
        self.exemptFilePattern = exemptFilePattern
    }
}
