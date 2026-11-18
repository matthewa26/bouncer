/// The resolved, per-rule configuration a `RuleRegistry` builds rules from.
///
/// This is what "every check is individually configurable" means in practice:
/// a `RuleRegistry` never hardcodes whether a rule runs or how strict it is,
/// it reads that from the `RuleSettings` the caller (ultimately `.bouncer`)
/// supplied.
public struct RuleSettings: Sendable, Equatable {
    /// Whether the rule should run at all.
    public let enabled: Bool

    /// The severity findings from this rule are reported at.
    public let severity: Severity

    /// The rule's tunable thresholds, such as a maximum line count.
    public let parameters: RuleParameters

    /// The default settings a rule uses when `.bouncer` doesn't mention it.
    public static let defaultEnabled = RuleSettings(enabled: true, severity: .warning, parameters: .empty)

    /// Creates a rule's settings.
    ///
    /// - Parameters:
    ///   - enabled: Whether the rule should run at all.
    ///   - severity: The severity findings from this rule are reported at.
    ///   - parameters: The rule's tunable thresholds.
    public init(enabled: Bool, severity: Severity, parameters: RuleParameters) {
        self.enabled = enabled
        self.severity = severity
        self.parameters = parameters
    }
}
