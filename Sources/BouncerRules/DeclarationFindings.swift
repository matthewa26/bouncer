import Foundation
import BouncerCore

/// Turns a `DeclarationSummary` into findings for each shared AST-based rule.
///
/// Kept as pure functions over already-collected data, separate from any tree
/// walk, so every parser-backed analyzer shares one implementation of each rule.
public enum DeclarationFindings {
    public static let godClassRuleID = "god-class"

    /// Runs every shared AST-based rule, in a fixed order.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    ///   - naming: The language's identifier patterns.
    /// - Returns: The combined findings.
    public static func all(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext, naming: NamingPatterns
    ) -> [Finding] {
        markerFindings(summary, file: file, context: context)
            + longFunction(summary, file: file, context: context)
            + cyclomaticComplexity(summary, file: file, context: context)
            + missingDocumentation(summary, file: file, context: context)
            + namingConvention(summary, file: file, context: context, naming: naming)
            + highCoupling(summary, file: file, context: context)
            + switchOnTypeSmell(summary, file: file, context: context)
            + godClass(summary, file: file, context: context)
            + metricRules.flatMap { metricFindings($0, summary, file: file, context: context) }
    }

    /// Flags every collected marker, grouped by kind in `MarkerKind.allCases` order.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including each marker rule's resolved settings.
    /// - Returns: One finding per marker whose rule is enabled.
    public static func markerFindings(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        MarkerKind.allCases.flatMap { kind -> [Finding] in
            let settings = context.settings(for: kind.ruleID)
            guard settings.enabled else { return [] }
            return summary.markers.filter { $0.kind == kind }.map {
                finding(kind.ruleID, $0.line, kind.message, settings.severity, file)
            }
        }
    }

    /// A per-function limit on one `FunctionMetrics` measurement.
    struct MetricRule: Sendable {
        let ruleID: String
        let parameter: String
        let defaultLimit: Int
        let value: @Sendable (FunctionMetrics) -> Int
        let describe: @Sendable (Int) -> String
    }

    static let metricRules: [MetricRule] = [
        MetricRule(
            ruleID: "long-parameter-list", parameter: "maxParameters", defaultLimit: 5,
            value: { $0.parameterCount }, describe: { "\($0) parameters" }
        ),
        MetricRule(
            ruleID: "too-many-returns", parameter: "maxReturns", defaultLimit: 4,
            value: { $0.returnCount }, describe: { "\($0) return statements" }
        ),
        MetricRule(
            ruleID: "cognitive-complexity", parameter: "max", defaultLimit: 15,
            value: { $0.cognitiveComplexity }, describe: { "cognitive complexity \($0)" }
        ),
        MetricRule(
            ruleID: "nesting-depth", parameter: "maxDepth", defaultLimit: 4,
            value: { $0.maxNestingDepth }, describe: { "control flow nested \($0) deep" }
        )
    ]

    /// Flags every measured function over one metric rule's limit.
    ///
    /// - Parameters:
    ///   - rule: The metric and its configured limit.
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per function over the limit.
    static func metricFindings(
        _ rule: MetricRule, _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: rule.ruleID)
        guard settings.enabled else { return [] }
        let limit = settings.parameters.int(rule.parameter, default: rule.defaultLimit)
        return summary.functions.compactMap { function in
            guard let metrics = function.metrics, rule.value(metrics) > limit else { return nil }
            let measured = rule.describe(rule.value(metrics))
            let message = "Function \"\(function.name)\" has \(measured), over the \(limit) limit."
            return finding(rule.ruleID, function.startLine, message, settings.severity, file)
        }
    }

    /// Flags every function whose logical line count exceeds `maxLines`.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per over-long function.
    public static func longFunction(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: LongFunctionRule.ruleID)
        guard settings.enabled else { return [] }
        let maxLines = settings.parameters.int("maxLines", default: 40)
        let profile = LanguageProfile(lineCommentPrefixes: commentPrefixes(for: file.language))
        return summary.functions.compactMap {
            longFunctionFinding($0, file: file, profile: profile, maxLines: maxLines, severity: settings.severity)
        }
    }

    /// Flags every function whose branch count exceeds `max`.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per over-complex function.
    public static func cyclomaticComplexity(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: CyclomaticComplexityRule.ruleID)
        guard settings.enabled else { return [] }
        let max = settings.parameters.int("max", default: 10)
        return summary.functions.compactMap { complexityFinding($0, file: file, max: max, severity: settings.severity) }
    }

    /// Flags every named function without a doc comment; anonymous callbacks have nothing to document.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per undocumented function.
    public static func missingDocumentation(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: MissingDocumentationRule.ruleID)
        guard settings.enabled else { return [] }
        let scope = settings.parameters.string("scope", default: "public")
        return summary.functions.filter { needsDocumentation($0, scope: scope) }.map { function in
            let message = "Function \"\(function.name)\" has no doc comment above its declaration."
            return finding(MissingDocumentationRule.ruleID, function.startLine, message, settings.severity, file)
        }
    }

    /// Reports whether a function is named, undocumented, and inside the configured visibility scope.
    ///
    /// - Parameters:
    ///   - function: The collected function.
    ///   - scope: The `missing-documentation` rule's `scope` parameter.
    /// - Returns: Whether the function should be flagged.
    private static func needsDocumentation(_ function: CollectedFunction, scope: String) -> Bool {
        guard !function.hasDocComment, function.name != CollectedFunction.anonymousName else { return false }
        return function.visibility.isIncluded(inScope: scope)
    }

    /// Flags every function or type name that doesn't match this language's naming pattern.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    ///   - naming: The language's naming patterns.
    /// - Returns: One finding per badly-named function or type.
    public static func namingConvention(
        _ summary: DeclarationSummary, file: SourceFile,
        context: AnalysisContext, naming: NamingPatterns
    ) -> [Finding] {
        let settings = context.settings(for: NamingConventionRule.ruleID)
        guard settings.enabled else { return [] }
        let severity = settings.severity
        let functions = summary.functions.compactMap {
            badlyNamed($0.name, naming.function, "function", $0.startLine, file, severity)
        }
        return functions + badlyNamedTypes(summary, naming: naming, file: file, severity: severity)
    }

    /// Flags the file once if its import count exceeds `maxImports`.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: A single finding, or none.
    public static func highCoupling(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: HighCouplingRule.ruleID)
        let maxImports = settings.parameters.int("maxImports", default: 15)
        guard settings.enabled, summary.importCount > maxImports else { return [] }
        let message = "File imports \(summary.importCount) modules, over the \(maxImports)-import coupling threshold."
        return [finding(HighCouplingRule.ruleID, 1, message, settings.severity, file)]
    }

    /// Flags every switch/match statement whose branch count exceeds `maxBranches`.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per over-large switch statement.
    public static func switchOnTypeSmell(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: SwitchOnTypeSmellRule.ruleID)
        let maxBranches = settings.parameters.int("maxBranches", default: 6)
        guard settings.enabled else { return [] }
        return summary.switches.filter { $0.caseCount > maxBranches }.map {
            switchFinding($0, file: file, maxBranches: maxBranches, severity: settings.severity)
        }
    }

    /// Flags every class whose combined member count and file-level coupling look like a god class.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per oversized, over-coupled class.
    public static func godClass(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: godClassRuleID)
        guard settings.enabled else { return [] }
        let thresholds = GodClassThresholds(settings: settings)
        return summary.types.compactMap {
            godClassFinding($0, file: file, importCount: summary.importCount, thresholds: thresholds)
        }
    }

    /// The `god-class` rule's thresholds, bundled to keep call sites short.
    private struct GodClassThresholds {
        let maxMembers: Int
        let maxImports: Int
        let severity: Severity

        /// Reads this rule's thresholds out of its resolved settings.
        ///
        /// - Parameter settings: The rule's resolved settings.
        init(settings: RuleSettings) {
            maxMembers = settings.parameters.int("maxMembers", default: 20)
            maxImports = settings.parameters.int("maxImportsForGodClass", default: 10)
            severity = settings.severity
        }
    }

    /// Looks up the comment prefixes for a language, for logical-line counting.
    ///
    /// - Parameter language: The language to look up.
    /// - Returns: Its line-comment prefixes.
    private static func commentPrefixes(for language: Language) -> [String] {
        LanguageProfiles.profile(for: language).lineCommentPrefixes
    }

    /// Builds a finding, folding in a file's path so call sites only pass the file itself.
    ///
    /// - Parameters:
    ///   - ruleID: The rule producing this finding.
    ///   - line: The finding's line.
    ///   - message: A human-readable explanation.
    ///   - severity: The severity to report at.
    ///   - file: The file the finding applies to.
    /// - Returns: The constructed finding.
    private static func finding(
        _ ruleID: String, _ line: Int, _ message: String, _ severity: Severity, _ file: SourceFile
    ) -> Finding {
        Finding(ruleID: ruleID, severity: severity, filePath: file.path, line: line, message: message)
    }

    /// Builds a finding for one function if it exceeds `maxLines`.
    ///
    /// - Parameters:
    ///   - function: The collected function.
    ///   - file: The file the function belongs to.
    ///   - profile: The comment-syntax profile used to count logical lines.
    ///   - maxLines: The configured maximum logical line count.
    ///   - severity: The severity to report at.
    /// - Returns: A finding, or `nil` if within the limit.
    private static func longFunctionFinding(
        _ function: CollectedFunction, file: SourceFile, profile: LanguageProfile, maxLines: Int, severity: Severity
    ) -> Finding? {
        let range = function.startLine...max(function.startLine, function.endLine)
        let count = LogicalLineCounter.count(in: file, range: range, profile: profile)
        guard count > maxLines else { return nil }
        let message = "Function \"\(function.name)\" has \(count) logical lines, over the \(maxLines)-line limit."
        return finding(LongFunctionRule.ruleID, function.startLine, message, severity, file)
    }

    /// Builds a finding for one function if its branch count exceeds `max`.
    ///
    /// - Parameters:
    ///   - function: The collected function.
    ///   - file: The file the function belongs to.
    ///   - max: The configured maximum complexity.
    ///   - severity: The severity to report at.
    /// - Returns: A finding, or `nil` if within the limit.
    private static func complexityFinding(
        _ function: CollectedFunction, file: SourceFile, max: Int, severity: Severity
    ) -> Finding? {
        let complexity = function.branchCount + 1
        guard complexity > max else { return nil }
        let message = "Function \"\(function.name)\" has complexity \(complexity), over the \(max) limit."
        return finding(CyclomaticComplexityRule.ruleID, function.startLine, message, severity, file)
    }

    /// Builds a finding for one switch/match statement.
    ///
    /// - Parameters:
    ///   - collectedSwitch: The collected switch/match statement.
    ///   - file: The file the switch belongs to.
    ///   - maxBranches: The configured maximum branch count.
    ///   - severity: The severity to report at.
    /// - Returns: The finding for this switch statement.
    private static func switchFinding(
        _ collectedSwitch: CollectedSwitch, file: SourceFile, maxBranches: Int, severity: Severity
    ) -> Finding {
        let message = "Switch has \(collectedSwitch.caseCount) branches, over the \(maxBranches)-branch limit."
        return finding(SwitchOnTypeSmellRule.ruleID, collectedSwitch.startLine, message, severity, file)
    }

    /// Builds a finding for one type if it looks like a god class.
    ///
    /// - Parameters:
    ///   - type: The collected type.
    ///   - file: The file the type belongs to.
    ///   - importCount: The file's total import count.
    ///   - thresholds: This rule's configured thresholds.
    /// - Returns: A finding, or `nil` if the type is within both limits.
    private static func godClassFinding(
        _ type: CollectedType, file: SourceFile, importCount: Int, thresholds: GodClassThresholds
    ) -> Finding? {
        guard type.memberCount > thresholds.maxMembers, importCount > thresholds.maxImports else { return nil }
        let message = "Type \"\(type.name)\" has \(type.memberCount) members in a file with \(importCount) imports."
        return finding(godClassRuleID, type.startLine, message, thresholds.severity, file)
    }

    /// Flags every collected type whose name doesn't match the language's type-naming pattern.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - naming: The language's naming patterns; languages without classes have no type pattern.
    ///   - file: The file being analyzed.
    ///   - severity: The severity to report at.
    /// - Returns: One finding per badly-named type.
    private static func badlyNamedTypes(
        _ summary: DeclarationSummary, naming: NamingPatterns, file: SourceFile, severity: Severity
    ) -> [Finding] {
        guard let pattern = naming.type else { return [] }
        return summary.types.compactMap { badlyNamed($0.name, pattern, "type", $0.startLine, file, severity) }
    }

    /// Builds a naming-convention finding if an identifier doesn't match its expected pattern.
    ///
    /// - Parameters:
    ///   - name: The declared identifier.
    ///   - pattern: The regex the identifier is expected to match.
    ///   - kind: A short label for the finding's message, such as `"function"`.
    ///   - line: The declaration's line.
    ///   - file: The file the declaration belongs to.
    ///   - severity: The severity to report at.
    /// - Returns: A finding, or `nil` if the identifier matches `pattern`.
    private static func badlyNamed(
        _ name: String, _ pattern: String, _ kind: String, _ line: Int, _ file: SourceFile, _ severity: Severity
    ) -> Finding? {
        guard let first = name.first, first.isLetter || first == "_" else { return nil }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        guard regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) == nil else { return nil }
        let message = "\(kind) \"\(name)\" doesn't match the expected naming convention."
        return finding(NamingConventionRule.ruleID, line, message, severity, file)
    }
}
