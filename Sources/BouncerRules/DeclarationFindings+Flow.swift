import Foundation
import BouncerCore

/// The control-flow, Halstead, maintainability, recursion, and test-shape rules, and the class and
/// doc rules they run alongside.
extension DeclarationFindings {
    static let flowMetricRules: [MetricRule] = [
        MetricRule(
            ruleID: "npath-complexity", parameter: "max", defaultLimit: 200,
            value: { $0.flow.npath }, describe: describeNPath, optIn: true
        ),
        MetricRule(
            ruleID: "arrow-code", parameter: "maxDepth", defaultLimit: 2,
            value: { $0.flow.arrowDepth },
            describe: { "\($0) nested ifs with no code after them (invert them into guard clauses)" }
        ),
        MetricRule(
            ruleID: "too-many-loop-jumps", parameter: "maxJumps", defaultLimit: 3,
            value: { $0.flow.maxLoopJumps }, describe: { "a loop with \($0) break/continue statements" }
        )
    ]

    /// Describes an NPath value, noting when it hit the cap.
    ///
    /// - Parameter value: The NPath value.
    /// - Returns: The description for the finding message.
    @Sendable private static func describeNPath(_ value: Int) -> String {
        value >= PathCount.cap ? "NPath complexity of at least \(PathCount.cap)" : "NPath complexity \(value)"
    }

    /// Runs the rules added for control flow, Halstead measures, classes, docs, and tests.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including each rule's resolved settings.
    /// - Returns: The combined findings.
    static func designFindings(_ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext) -> [Finding] {
        maintainabilityIndex(summary, file: file, context: context)
            + halsteadComplexity(summary, file: file, context: context)
            + unboundedRecursion(summary, file: file, context: context)
            + oversizedTests(summary, file: file, context: context)
            + classDesignFindings(summary, file: file, context: context)
            + documentationFindings(summary, file: file, context: context)
    }

    /// Resolves a rule's settings: a default-on rule falls back to enabled, an opt-in one to off.
    ///
    /// - Parameters:
    ///   - ruleID: The rule.
    ///   - optIn: Whether it only runs when a config enables it.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The settings if the rule should run, else `nil`.
    static func enabledSettings(_ ruleID: String, optIn: Bool = false, context: AnalysisContext) -> RuleSettings? {
        let settings = optIn ? context.ruleSettings[ruleID] : context.settings(for: ruleID)
        return settings?.enabled == true ? settings : nil
    }

    /// Flags every function whose maintainability index falls below `minIndex`, on Visual Studio's 0–100
    /// scale: 100 × (171 − 5.2 ln(Halstead volume) − 0.23 × cyclomatic complexity − 16.2 ln(logical lines)) / 171.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per hard-to-maintain function.
    static func maintainabilityIndex(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        guard let settings = enabledSettings("maintainability-index", context: context) else { return [] }
        let minimum = settings.parameters.double("minIndex", default: 20)
        return summary.functions.compactMap { function in
            maintainabilityMessage(function, file: file, minimum: minimum).map {
                finding("maintainability-index", function.startLine, $0, settings.severity, file)
            }
        }
    }

    /// Checks one function's maintainability index against the minimum.
    ///
    /// - Parameters:
    ///   - function: The function.
    ///   - file: Its file, for counting logical lines.
    ///   - minimum: The lowest acceptable index.
    /// - Returns: The finding message, or `nil` if it's unmeasured or maintainable enough.
    private static func maintainabilityMessage(
        _ function: CollectedFunction, file: SourceFile, minimum: Double
    ) -> String? {
        guard let metrics = function.metrics else { return nil }
        let index = maintainability(function, metrics: metrics, file: file)
        guard index < minimum else { return nil }
        return "Function \"\(function.name)\" has maintainability index \(Int(index.rounded(.down))) "
            + "(Halstead volume \(Int(metrics.halstead.volume))), under the \(format(minimum)) minimum."
    }

    /// Computes a function's maintainability index on the 0–100 scale.
    ///
    /// - Parameters:
    ///   - function: The function.
    ///   - metrics: Its measurements.
    ///   - file: Its file, for counting logical lines.
    /// - Returns: The index, clamped at 0.
    static func maintainability(_ function: CollectedFunction, metrics: FunctionMetrics, file: SourceFile) -> Double {
        let lines = Double(max(1, logicalLines(of: function, in: file)))
        let raw = 171 - 5.2 * log(max(1, metrics.halstead.volume)) - 0.23 * Double(function.branchCount + 1)
            - 16.2 * log(lines)
        return max(0, raw * 100 / 171)
    }

    /// Flags every function over any of the Halstead limits; off unless configured.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per function over a limit, giving all three measures.
    static func halsteadComplexity(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        guard let settings = enabledSettings("halstead-complexity", optIn: true, context: context) else { return [] }
        let limits = HalsteadLimits(settings.parameters)
        return summary.functions.compactMap { function in
            guard let counts = function.metrics?.halstead, limits.isExceeded(by: counts) else { return nil }
            let message = "Function \"\(function.name)\" has Halstead volume \(Int(counts.volume)), difficulty "
                + "\(Int(counts.difficulty)), and effort \(Int(counts.effort)), over the limits "
                + "(\(format(limits.volume)), \(format(limits.difficulty)), \(format(limits.effort)))."
            return finding("halstead-complexity", function.startLine, message, settings.severity, file)
        }
    }

    /// The `halstead-complexity` rule's limits.
    private struct HalsteadLimits {
        let volume: Double
        let difficulty: Double
        let effort: Double

        /// Reads the limits from the rule's parameters.
        ///
        /// - Parameter parameters: The rule's parameters.
        init(_ parameters: RuleParameters) {
            volume = parameters.double("maxVolume", default: 1000)
            difficulty = parameters.double("maxDifficulty", default: 30)
            effort = parameters.double("maxEffort", default: 30000)
        }

        /// Reports whether counts exceed any limit.
        ///
        /// - Parameter counts: A function's Halstead counts.
        /// - Returns: Whether volume, difficulty, or effort is over its limit.
        func isExceeded(by counts: HalsteadCounts) -> Bool {
            counts.volume > volume || counts.difficulty > difficulty || counts.effort > effort
        }
    }

    /// Formats a limit without a trailing `.0`.
    ///
    /// - Parameter value: The limit.
    /// - Returns: Its text.
    static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    /// Flags every function that calls itself with no branch, loop, or early exit to stop it.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per unconditionally recursive function.
    static func unboundedRecursion(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        guard let settings = enabledSettings("recursion-without-base-case", context: context) else { return [] }
        return summary.functions.filter { $0.metrics?.flow.recursesWithoutBaseCase == true }.map { function in
            let message = "Function \"\(function.name)\" calls itself with no branch or early exit before it, "
                + "so the recursion has no base case."
            return finding("recursion-without-base-case", function.startLine, message, settings.severity, file)
        }
    }

    /// Flags every test in a test file that's longer than `maxLines` logical lines or makes more than
    /// `maxAssertions` assertions.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per oversized test.
    static func oversizedTests(_ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext) -> [Finding] {
        guard let settings = enabledSettings("oversized-test", context: context), isTestFile(file) else { return [] }
        let limits = (lines: settings.parameters.int("maxLines", default: 50),
                      assertions: settings.parameters.int("maxAssertions", default: 15))
        return summary.functions.compactMap { function in
            let over = testExcess(function, file: file, limits: limits)
            guard !over.isEmpty else { return nil }
            let message = "\(testLabel(function)) has \(over.joined(separator: " and ")); split it into focused tests."
            return finding("oversized-test", function.startLine, message, settings.severity, file)
        }
    }

    /// Lists how a test goes over its limits.
    ///
    /// - Parameters:
    ///   - function: The function.
    ///   - file: Its file, for counting logical lines.
    ///   - limits: The most logical lines and assertions allowed.
    /// - Returns: A phrase per exceeded limit; none for a function that isn't a test.
    private static func testExcess(
        _ function: CollectedFunction, file: SourceFile, limits: (lines: Int, assertions: Int)
    ) -> [String] {
        guard let assertions = function.metrics?.testAssertionCount else { return [] }
        let lines = logicalLines(of: function, in: file)
        return (lines > limits.lines ? ["\(lines) logical lines (limit \(limits.lines))"] : [])
            + (assertions > limits.assertions ? ["\(assertions) assertions (limit \(limits.assertions))"] : [])
    }

    /// Reports whether a file's path marks it as test code, as `Tests/`, `test_x.py`, `x_test.go`, and
    /// `x.spec.ts` do, so a helper that merely starts with `test` elsewhere isn't measured as a test.
    ///
    /// - Parameter file: The file.
    /// - Returns: Whether some path component mentions `test` or `spec`.
    private static func isTestFile(_ file: SourceFile) -> Bool {
        file.path.pathComponents.contains { DocCommentParser.matches("test|spec", $0) }
    }

    /// Counts a function's logical lines, as `long-function` does.
    ///
    /// - Parameters:
    ///   - function: The function.
    ///   - file: Its file.
    /// - Returns: Its non-blank, non-comment lines.
    private static func logicalLines(of function: CollectedFunction, in file: SourceFile) -> Int {
        let profile = LanguageProfile(lineCommentPrefixes: commentPrefixes(for: file.language))
        return LogicalLineCounter.count(in: file, range: function.startLine...max(function.startLine, function.endLine),
                                        profile: profile)
    }

    /// Names a test for a finding message; a test callback such as `it("…", () => {})` has no name.
    ///
    /// - Parameter function: The test function.
    /// - Returns: `Test "name"`, or just `Test`.
    private static func testLabel(_ function: CollectedFunction) -> String {
        function.name == CollectedFunction.anonymousName ? "Test" : "Test \"\(function.name)\""
    }
}
