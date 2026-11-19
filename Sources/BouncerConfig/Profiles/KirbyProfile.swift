import BouncerCore
import BouncerRules

/// The `kirby` bundled preset, named for Professor Neil Kirby (OSU CSE 3902,
/// formerly Bell Labs), whose teaching on simplicity, low coupling and high
/// cohesion, and eliminating code smells shaped this rule catalog. These are
/// Bouncer's own best-effort calibration of that philosophy into numbers,
/// not published thresholds, and remain fully overridable by config layers
/// applied on top.
public enum KirbyProfile {
    /// This preset's config, applied as the base layer beneath `~/.bouncer` and a repo's `.bouncer`.
    public static let config = BouncerConfig(
        coverage: CoverageConfig(threshold: 90),
        rules: [
            "long-function": entry(severity: .error, params: ["maxLines": .int(10)]),
            "cyclomatic-complexity": entry(severity: .error, params: ["max": .int(6)]),
            "naming-convention": entry(severity: .error),
            "missing-documentation": entry(severity: .error, params: ["scope": .string("all")]),
            "high-coupling": entry(severity: .error, params: ["maxImports": .int(8)]),
            "god-class": entry(severity: .error),
            "switch-on-type-smell": entry(severity: .error, params: ["maxBranches": .int(3)]),
            "long-parameter-list": entry(severity: .error, params: ["maxParameters": .int(3)]),
            "too-many-returns": entry(severity: .error, params: ["maxReturns": .int(3)]),
            "cognitive-complexity": entry(severity: .error, params: ["max": .int(8)]),
            "nesting-depth": entry(severity: .error, params: ["maxDepth": .int(3)]),
            "boolean-parameter": entry(severity: .error, params: ["maxBooleanParameters": .int(0)]),
            "lack-of-cohesion": entry(severity: .error, params: ["maxGroups": .int(1)]),
            "type-check-chain": entry(severity: .error, params: ["maxTypeChecks": .int(1)]),
            "long-message-chain": entry(severity: .error, params: ["maxCalls": .int(4)]),
            "data-class": entry(severity: .error),
            "global-mutable-state": entry(severity: .error)
        ].merging(smellsAsErrors) { explicit, _ in explicit }
    )

    /// Single-location smells Kirby mode treats as errors instead of warnings.
    private static let smellsAsErrors: [String: RuleConfigEntry] = Dictionary(
        uniqueKeysWithValues: MarkerKind.allCases.map { ($0.ruleID, entry(severity: .error)) }
    )

    /// Builds one rule's enabled, at-severity entry with optional parameters.
    ///
    /// - Parameters:
    ///   - severity: The severity to report the rule's findings at.
    ///   - params: The rule's tunable thresholds.
    /// - Returns: The constructed entry.
    private static func entry(severity: Severity, params: [String: RuleParamValue] = [:]) -> RuleConfigEntry {
        RuleConfigEntry(enabled: true, severity: severity, params: params.isEmpty ? nil : params)
    }
}
