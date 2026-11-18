import Foundation
import BouncerCore
import BouncerRules

/// Turns a `TreeSitterDeclarationSummary` into findings for each AST-based rule.
///
/// Kept as pure functions over already-collected data, separate from the tree
/// walk itself, matching the pattern `SwiftASTFindings` already established.
enum TreeSitterASTFindings {
    static let godClassRuleID = "god-class"

    /// Flags every function whose logical line count exceeds `maxLines`.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's parse tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per over-long function.
    static func longFunction(
        _ summary: TreeSitterDeclarationSummary, file: SourceFile, context: AnalysisContext
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
    ///   - summary: The declarations collected from the file's parse tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per over-complex function.
    static func cyclomaticComplexity(
        _ summary: TreeSitterDeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: CyclomaticComplexityRule.ruleID)
        guard settings.enabled else { return [] }
        let max = settings.parameters.int("max", default: 10)
        return summary.functions.compactMap { complexityFinding($0, file: file, max: max, severity: settings.severity) }
    }

    /// Flags every function without a doc comment.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's parse tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per undocumented function.
    static func missingDocumentation(
        _ summary: TreeSitterDeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: MissingDocumentationRule.ruleID)
        guard settings.enabled else { return [] }
        let scope = settings.parameters.string("scope", default: "public")
        let undocumented = summary.functions.filter { !$0.hasDocComment && $0.visibility.isIncluded(inScope: scope) }
        return undocumented.map { function in
            let message = "Function \"\(function.name)\" has no doc comment above its declaration."
            return finding(MissingDocumentationRule.ruleID, function.startLine, message, settings.severity, file)
        }
    }

    /// Flags every function or type name that doesn't match this language's naming pattern.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's parse tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    ///   - spec: The language's naming patterns.
    /// - Returns: One finding per badly-named function or type.
    static func namingConvention(
        _ summary: TreeSitterDeclarationSummary, file: SourceFile,
        context: AnalysisContext, spec: TreeSitterLanguageSpec
    ) -> [Finding] {
        let settings = context.settings(for: NamingConventionRule.ruleID)
        guard settings.enabled else { return [] }
        let severity = settings.severity
        let functions = summary.functions.compactMap {
            badlyNamed($0.name, spec.functionNamePattern, "function", $0.startLine, file, severity)
        }
        return functions + badlyNamedTypes(summary, spec: spec, file: file, severity: severity)
    }

    /// Flags the file once if its import count exceeds `maxImports`.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's parse tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: A single finding, or none.
    static func highCoupling(
        _ summary: TreeSitterDeclarationSummary, file: SourceFile, context: AnalysisContext
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
    ///   - summary: The declarations collected from the file's parse tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per over-large switch statement.
    static func switchOnTypeSmell(
        _ summary: TreeSitterDeclarationSummary, file: SourceFile, context: AnalysisContext
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
    ///   - summary: The declarations collected from the file's parse tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per oversized, over-coupled class.
    static func godClass(
        _ summary: TreeSitterDeclarationSummary, file: SourceFile, context: AnalysisContext
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
        _ function: TSCollectedFunction, file: SourceFile, profile: LanguageProfile, maxLines: Int, severity: Severity
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
        _ function: TSCollectedFunction, file: SourceFile, max: Int, severity: Severity
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
        _ collectedSwitch: TSCollectedSwitch, file: SourceFile, maxBranches: Int, severity: Severity
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
        _ type: TSCollectedType, file: SourceFile, importCount: Int, thresholds: GodClassThresholds
    ) -> Finding? {
        guard type.memberCount > thresholds.maxMembers, importCount > thresholds.maxImports else { return nil }
        let message = "Type \"\(type.name)\" has \(type.memberCount) members in a file with \(importCount) imports."
        return finding(godClassRuleID, type.startLine, message, thresholds.severity, file)
    }

    /// Flags every collected type whose name doesn't match the language's type-naming pattern.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's parse tree.
    ///   - spec: The language's naming patterns; languages without classes have no type pattern.
    ///   - file: The file being analyzed.
    ///   - severity: The severity to report at.
    /// - Returns: One finding per badly-named type.
    private static func badlyNamedTypes(
        _ summary: TreeSitterDeclarationSummary, spec: TreeSitterLanguageSpec, file: SourceFile, severity: Severity
    ) -> [Finding] {
        guard let pattern = spec.typeNamePattern else { return [] }
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
