import BouncerCore
import BouncerRules

/// One entry in `.bouncer`'s `customRules` array.
public struct CustomRuleConfigEntry: Codable, Sendable, Equatable {
    public var id: String
    public var type: String
    public var pattern: String?
    public var message: String?
    public var severity: Severity?

    /// Creates a custom rule entry.
    ///
    /// - Parameters:
    ///   - id: The rule's stable identifier.
    ///   - type: The rule kind. Only `"pattern"` is supported in v1.
    ///   - pattern: The regular expression a matching line must contain.
    ///   - message: The message shown for a match.
    ///   - severity: The severity to report matches at.
    public init(id: String, type: String, pattern: String? = nil, message: String? = nil, severity: Severity? = nil) {
        self.id = id
        self.type = type
        self.pattern = pattern
        self.message = message
        self.severity = severity
    }

    /// Converts this entry into a `PatternRuleSpec`, if it's a valid pattern rule.
    ///
    /// - Returns: The equivalent spec, or `nil` for an unsupported `type` or missing fields.
    public func patternRuleSpec() -> PatternRuleSpec? {
        guard type == "pattern", let pattern, let message else { return nil }
        return PatternRuleSpec(id: id, pattern: pattern, message: message)
    }
}
