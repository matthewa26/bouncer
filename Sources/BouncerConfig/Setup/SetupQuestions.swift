import BouncerCore
import BouncerRules

/// One integer rule threshold the setup wizard asks about, with the default its rule uses when unset.
public struct SetupThreshold: Sendable, Equatable {
    /// The rule's identifier, the key under `.bouncer`'s `rules`.
    public let ruleID: String
    /// The parameter's key under the rule's `params`.
    public let parameter: String
    /// The value the rule uses when nothing configures it.
    public let defaultValue: Int
    /// The answers the wizard accepts.
    public let range: ClosedRange<Int>
    /// The question shown to the user.
    public let question: String

    /// The thresholds the wizard asks about, in order. Defaults mirror each rule's inline default.
    public static let all: [SetupThreshold] = [
        SetupThreshold(LongFunctionRule.ruleID, "maxLines", 40, 1...1_000, "Max logical lines per function"),
        SetupThreshold(LongLineRule.ruleID, "maxLength", 120, 40...1_000, "Max characters per line"),
        SetupThreshold(FileLengthRule.ruleID, "maxLines", 500, 1...100_000, "Max logical lines per file"),
        SetupThreshold(CyclomaticComplexityRule.ruleID, "max", 10, 1...100, "Max cyclomatic complexity per function"),
        SetupThreshold("cognitive-complexity", "max", 15, 1...200, "Max cognitive complexity per function"),
        SetupThreshold("long-parameter-list", "maxParameters", 5, 0...50, "Max parameters per function"),
        SetupThreshold("nesting-depth", "maxDepth", 4, 1...20, "Max control-flow nesting depth per function")
    ]

    /// Creates a threshold description.
    ///
    /// - Parameters:
    ///   - ruleID: The rule's identifier.
    ///   - parameter: The parameter's key.
    ///   - defaultValue: The rule's built-in default.
    ///   - range: The accepted answers.
    ///   - question: The question text, without the rule ID.
    private init(
        _ ruleID: String, _ parameter: String, _ defaultValue: Int, _ range: ClosedRange<Int>, _ question: String
    ) {
        self.ruleID = ruleID
        self.parameter = parameter
        self.defaultValue = defaultValue
        self.range = range
        self.question = "\(question) (\(ruleID).\(parameter))"
    }

    /// The value this threshold has in a config, or the rule's default when unset.
    ///
    /// - Parameter config: The config to read.
    /// - Returns: The configured integer, clamped into `range`.
    public func current(in config: BouncerConfig) -> Int {
        let configured: Int
        switch config.rules?[ruleID]?.params?[parameter] {
        case .int(let value)?: configured = value
        case .double(let value)?: configured = Int(value)
        default: configured = defaultValue
        }
        return min(max(configured, range.lowerBound), range.upperBound)
    }
}

/// The setup wizard's questions, each recording only answers that differ from the starting point.
struct SetupQuestions {
    /// The verbosity names `OutputVerbosity` decodes, in the order offered.
    static let verbosities = ["normal", "verbose", "quiet", "condensed"]
    /// The `missing-documentation` choices: off, or one of its `scope` values.
    static let documentationScopes = ["off", "public", "internal", "all"]
    /// The coverage threshold the coverage check uses when none is configured.
    static let defaultCoverageThreshold = 80.0

    /// A repo with fewer analyzable files than this gets `immediate` refresh recommended, a larger one `next-scan`.
    static let immediateRefreshFileCutoff = 5_000
    /// The refresh question, as the user sees it.
    static let refreshQuestion = "When files change while an agent is working, when should Bouncer notice?"
    /// The refresh choices, in the order offered.
    static let refreshChoices: [AgentRefresh] = [.nextScan, .immediate]

    /// The question-asking I/O.
    let prompt: Prompt
    /// The starting point every answer defaults to and is compared with.
    let base: BouncerConfig
    /// Counts the repo's analyzable files, for the refresh recommendation; called only when that question is asked.
    let countFiles: () -> Int

    /// Asks every question.
    ///
    /// - Returns: A config holding only the settings whose answers differ from `base`.
    /// - Throws: `PromptError.endOfInput` if input ends first.
    func ask() throws -> BouncerConfig {
        var changes = BouncerConfig.empty
        changes.output = try askOutput()
        changes.coverage = try askCoverage()
        changes.rules = try askRules()
        changes.agent = try askAgent()
        return changes
    }

    /// Asks for console verbosity.
    ///
    /// - Returns: The changed output section, or `nil` if unchanged.
    /// - Throws: `PromptError.endOfInput` if input ends first.
    private func askOutput() throws -> OutputConfig? {
        let current = base.output?.verbosity ?? .normal
        let question = "Console output verbosity?"
        let answer = try prompt.choice(question, options: Self.verbosities, default: current.rawValue)
        guard let picked = OutputVerbosity(rawValue: answer), picked != current else { return nil }
        return OutputConfig(verbosity: picked)
    }

    /// Asks whether to check coverage, and if so, its threshold and report path.
    ///
    /// - Returns: The changed coverage section, or `nil` if unchanged.
    /// - Throws: `PromptError.endOfInput` if input ends first.
    private func askCoverage() throws -> CoverageConfig? {
        let current = base.coverage ?? CoverageConfig()
        let enabled = try prompt.yesNo("Check test coverage?", default: current.enabled ?? false)
        var changes = try enabled ? askCoverageDetails(current) : CoverageConfig()
        if enabled != (current.enabled ?? false) { changes.enabled = enabled }
        return changes == CoverageConfig() ? nil : changes
    }

    /// Asks for the coverage threshold and report path.
    ///
    /// - Parameter current: The starting point's coverage section.
    /// - Returns: The changed threshold and report path, if any.
    /// - Throws: `PromptError.endOfInput` if input ends first.
    private func askCoverageDetails(_ current: CoverageConfig) throws -> CoverageConfig {
        let threshold = current.threshold ?? Self.defaultCoverageThreshold
        let answer = try prompt.integer("Minimum line coverage percentage", default: Int(threshold), range: 0...100)
        let path = try prompt.text("Coverage report path (blank to auto-detect)", default: current.reportPath ?? "")
        return CoverageConfig(
            reportPath: path == (current.reportPath ?? "") ? nil : path,
            threshold: Double(answer) == threshold ? nil : Double(answer)
        )
    }

    /// Asks for every rule threshold and toggle.
    ///
    /// - Returns: The changed rule entries, or `nil` if none changed.
    /// - Throws: `PromptError.endOfInput` if input ends first.
    private func askRules() throws -> [String: RuleConfigEntry]? {
        var rules = try askThresholds()
        rules[MarkerKind.magicNumber.ruleID] = try askMagicNumber()
        rules[MissingDocumentationRule.ruleID] = try askDocumentation()
        return rules.isEmpty ? nil : rules
    }

    /// Asks for every integer threshold in `SetupThreshold.all`.
    ///
    /// - Returns: An entry per rule whose answer differs from the starting point.
    /// - Throws: `PromptError.endOfInput` if input ends first.
    private func askThresholds() throws -> [String: RuleConfigEntry] {
        var rules: [String: RuleConfigEntry] = [:]
        for threshold in SetupThreshold.all {
            let current = threshold.current(in: base)
            let answer = try prompt.integer(threshold.question, default: current, range: threshold.range)
            guard answer != current else { continue }
            rules[threshold.ruleID] = RuleConfigEntry(params: [threshold.parameter: .int(answer)])
        }
        return rules
    }

    /// Asks whether `magic-number` should run.
    ///
    /// - Returns: The changed entry, or `nil` if unchanged.
    /// - Throws: `PromptError.endOfInput` if input ends first.
    private func askMagicNumber() throws -> RuleConfigEntry? {
        let ruleID = MarkerKind.magicNumber.ruleID
        let current = base.rules?[ruleID]?.enabled ?? true
        let answer = try prompt.yesNo("Flag unnamed numeric literals (\(ruleID))?", default: current)
        return answer == current ? nil : RuleConfigEntry(enabled: answer)
    }

    /// Asks whether `missing-documentation` should run, and at which `scope`.
    ///
    /// - Returns: The changed entry, or `nil` if unchanged.
    /// - Throws: `PromptError.endOfInput` if input ends first.
    private func askDocumentation() throws -> RuleConfigEntry? {
        let ruleID = MissingDocumentationRule.ruleID
        let current = documentationChoice(base.rules?[ruleID])
        let question = "Require doc comments (\(ruleID)): off, or which declarations?"
        let answer = try prompt.choice(question, options: Self.documentationScopes, default: current)
        guard answer != current else { return nil }
        return answer == "off" ? RuleConfigEntry(enabled: false) : RuleConfigEntry(
            enabled: true, params: ["scope": .string(answer)]
        )
    }

    /// Describes a `missing-documentation` entry as one of `documentationScopes`.
    ///
    /// - Parameter entry: The configured entry, if any.
    /// - Returns: `"off"` when disabled, otherwise its scope (default `"public"`).
    private func documentationChoice(_ entry: RuleConfigEntry?) -> String {
        guard entry?.enabled != false else { return "off" }
        guard case .string(let scope)? = entry?.params?["scope"] else { return "public" }
        return scope
    }

    /// Asks when a long-lived agent session should notice changed files, recommending by the repo's size.
    ///
    /// The blank-answer default is the starting point's setting, or the recommendation when it has none.
    ///
    /// - Returns: The changed agent section, or `nil` if the answer matches the starting point (default `next-scan`).
    /// - Throws: `PromptError.endOfInput` if input ends first.
    private func askAgent() throws -> AgentConfig? {
        let current = base.agent?.refresh ?? .nextScan
        let recommended: AgentRefresh = countFiles() < Self.immediateRefreshFileCutoff ? .immediate : .nextScan
        let options = Self.refreshChoices.map { refreshOption($0, recommended: recommended) }
        let initial = Self.refreshChoices.firstIndex(of: base.agent?.refresh ?? recommended) ?? 0
        let index = try prompt.choice(Self.refreshQuestion, described: options, default: initial)
        let picked = Self.refreshChoices[index]
        return picked == current ? nil : AgentConfig(refresh: picked)
    }

    /// Describes one refresh choice, noting it as recommended when it is.
    ///
    /// - Parameters:
    ///   - refresh: The choice.
    ///   - recommended: The choice the repo's size suggests.
    /// - Returns: The option to show.
    private func refreshOption(_ refresh: AgentRefresh, recommended: AgentRefresh) -> PromptOption {
        switch refresh {
        case .nextScan:
            let note = refresh == recommended ? " (recommended for large repos)" : ""
            return PromptOption("On the next scan" + note, detail: Self.nextScanDetail)
        case .immediate:
            let note = refresh == recommended ? " (recommended for this repo's size)" : ""
            return PromptOption("Immediately" + note, detail: Self.immediateDetail)
        }
    }

    /// What `next-scan` means, under its option.
    private static let nextScanDetail =
        "Results stay as they were until the agent scans again or verifies the files it edited."
    /// What `immediate` means, under its option.
    private static let immediateDetail =
        "Before every answer, Bouncer re-checks any file that changed. Always current, but slower on large repos."
}
