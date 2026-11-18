/// A single check that inspects a file and reports violations.
///
/// Implementations are constructed with their `RuleSettings` already resolved
/// by a `RuleRegistry`, so a `Rule` itself never reaches into config directly.
public protocol Rule: Sendable {
    /// The rule's stable identifier, such as `"long-function"`.
    ///
    /// This is the key `.bouncer` uses to configure the rule, so it must never
    /// change once shipped.
    var id: String { get }

    /// Inspects a file and returns every violation found.
    ///
    /// - Parameters:
    ///   - file: The file to inspect.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: Zero or more findings.
    func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding]
}
