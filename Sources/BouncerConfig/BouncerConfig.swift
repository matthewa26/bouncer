import BouncerCore

/// The parsed, still-layered contents of a `.bouncer` file.
///
/// Every field is optional so that `~/.bouncer`, a repo's `.bouncer`, a
/// selected profile, and CLI flags can each supply only what they care about,
/// with `merging(_:)` combining them into one resolved config.
public struct BouncerConfig: Codable, Sendable, Equatable {
    public var output: OutputConfig?
    public var coverage: CoverageConfig?
    public var rules: [String: RuleConfigEntry]?
    public var customRules: [CustomRuleConfigEntry]?
    public var hooks: HooksConfig?
    public var updateCheck: UpdateCheckConfig?
    public var profile: String?
    public var exclude: [String]?

    /// An empty config, equivalent to "nothing configured at this layer."
    public static let empty = BouncerConfig()

    /// Creates a config from its sections.
    ///
    /// - Parameters:
    ///   - output: Console output preferences.
    ///   - coverage: Coverage checking configuration.
    ///   - rules: Per-rule overrides, keyed by rule identifier.
    ///   - customRules: User-declared pattern rules.
    ///   - hooks: Pre/post check shell commands.
    ///   - updateCheck: Update-check configuration.
    ///   - profile: A bundled preset to apply as a base layer, such as `"kirby"`.
    ///   - exclude: Glob patterns to exclude from analysis.
    public init(
        output: OutputConfig? = nil, coverage: CoverageConfig? = nil, rules: [String: RuleConfigEntry]? = nil,
        customRules: [CustomRuleConfigEntry]? = nil, hooks: HooksConfig? = nil, updateCheck: UpdateCheckConfig? = nil,
        profile: String? = nil, exclude: [String]? = nil
    ) {
        self.output = output
        self.coverage = coverage
        self.rules = rules
        self.customRules = customRules
        self.hooks = hooks
        self.updateCheck = updateCheck
        self.profile = profile
        self.exclude = exclude
    }

    /// Merges another config's fields over this one's.
    ///
    /// Scalars and sections prefer `other`'s value when both are set; `rules`
    /// merges key-by-key with each entry's own field-level merge; `hooks`
    /// concatenates rather than overrides, since both layers' hooks should run.
    ///
    /// - Parameter other: The higher-precedence config.
    /// - Returns: The merged config.
    public func merging(_ other: BouncerConfig) -> BouncerConfig {
        let sections = mergedSections(with: other)
        return BouncerConfig(
            output: sections.output, coverage: sections.coverage, rules: mergedRules(with: other.rules),
            customRules: other.customRules ?? customRules, hooks: sections.hooks, updateCheck: sections.updateCheck,
            profile: other.profile ?? profile, exclude: other.exclude ?? exclude
        )
    }

    /// Merges the four sections that all follow the same optional-pair merge pattern.
    ///
    /// - Parameter other: The higher-precedence config.
    /// - Returns: The merged `output`, `coverage`, `hooks`, and `updateCheck` sections.
    private func mergedSections(
        with other: BouncerConfig
    ) -> (output: OutputConfig?, coverage: CoverageConfig?, hooks: HooksConfig?, updateCheck: UpdateCheckConfig?) {
        (
            mergedOptional(output, other.output) { $0.merging($1) },
            mergedOptional(coverage, other.coverage) { $0.merging($1) },
            mergedOptional(hooks, other.hooks) { $0.merging($1) },
            mergedOptional(updateCheck, other.updateCheck) { $0.merging($1) }
        )
    }

    /// Resolves `rules` into the `[String: RuleSettings]` an `AnalysisContext` needs.
    ///
    /// - Returns: Every configured rule's resolved settings.
    public func resolvedRuleSettings() -> [String: RuleSettings] {
        (rules ?? [:]).mapValues { $0.resolved() }
    }

    /// Merges two optional sections, keeping whichever side is present when only one is.
    ///
    /// - Parameters:
    ///   - lhs: This config's section.
    ///   - rhs: The other config's section.
    ///   - combine: How to merge both sections when both are present.
    /// - Returns: The merged section, or whichever side is non-`nil`.
    private func mergedOptional<T>(_ lhs: T?, _ rhs: T?, combine: (T, T) -> T) -> T? {
        switch (lhs, rhs) {
        case (let a?, let b?): return combine(a, b)
        case (let a?, nil): return a
        case (nil, let b?): return b
        case (nil, nil): return nil
        }
    }

    /// Merges `rules` dictionaries key-by-key, combining each shared entry's own fields.
    ///
    /// - Parameter otherRules: The higher-precedence config's `rules`.
    /// - Returns: The merged dictionary, or `nil` if neither side has any.
    private func mergedRules(with otherRules: [String: RuleConfigEntry]?) -> [String: RuleConfigEntry]? {
        guard rules != nil || otherRules != nil else { return nil }
        var result = rules ?? [:]
        for (key, value) in otherRules ?? [:] {
            result[key] = result[key]?.merging(value) ?? value
        }
        return result
    }
}
