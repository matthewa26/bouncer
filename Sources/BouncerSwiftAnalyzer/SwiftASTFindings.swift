import Foundation
import BouncerCore
import BouncerRules

/// Turns a `SwiftDeclarationSummary` into findings for the Swift-only rules, plus the shared ones.
///
/// Kept as pure functions over already-collected data, separate from the tree
/// walk itself, so each rule's logic is easy to read and test in isolation.
enum SwiftASTFindings {
    static let forceUnwrapRuleID = "force-unwrap"
    static let forceTryRuleID = "force-try"
    private static let naming = NamingPatterns(function: "^[a-z_][A-Za-z0-9_]*$", type: "^[A-Z][A-Za-z0-9_]*$")

    /// Flags every force-unwrap expression.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per force-unwrap expression.
    static func forceUnwrap(
        _ summary: SwiftDeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: forceUnwrapRuleID)
        guard settings.enabled else { return [] }
        let message = "Force unwrap can crash at runtime."
        return summary.forceUnwrapLines.map { finding(forceUnwrapRuleID, $0, message, settings.severity, file) }
    }

    /// Flags every force-try expression.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per force-try expression.
    static func forceTry(_ summary: SwiftDeclarationSummary, file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: forceTryRuleID)
        guard settings.enabled else { return [] }
        let message = "Force try can crash at runtime."
        return summary.forceTryLines.map { finding(forceTryRuleID, $0, message, settings.severity, file) }
    }

    /// Runs every shared AST-based rule with Swift's naming conventions.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The combined findings from every shared rule.
    static func shared(_ summary: SwiftDeclarationSummary, file: SourceFile, context: AnalysisContext) -> [Finding] {
        DeclarationFindings.all(summary.declarations, file: file, context: context, naming: naming)
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
}
