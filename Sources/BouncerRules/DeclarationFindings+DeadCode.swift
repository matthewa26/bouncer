import BouncerCore

/// The dead-code rules: unused private symbols, imports, and parameters.
extension DeclarationFindings {
    /// Flags every unused declaration whose rule is enabled, grouped by kind in `DeadCodeKind.allCases` order.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including each dead-code rule's resolved settings.
    /// - Returns: One finding per unused declaration.
    static func deadCodeFindings(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        DeadCodeKind.allCases.flatMap { kind -> [Finding] in
            guard let settings = deadCodeSettings(kind, context: context) else { return [] }
            return summary.unusedDeclarations.filter { $0.kind == kind }.map {
                finding(kind.ruleID, $0.line, $0.message, settings.severity, file)
            }
        }
    }

    /// Resolves a dead-code rule's settings: default-on rules fall back to enabled, opt-in ones to off.
    ///
    /// - Parameters:
    ///   - kind: The dead-code kind.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The settings if the rule should run, else `nil`.
    private static func deadCodeSettings(_ kind: DeadCodeKind, context: AnalysisContext) -> RuleSettings? {
        let settings = kind.isOptIn ? context.ruleSettings[kind.ruleID] : context.settings(for: kind.ruleID)
        return settings?.enabled == true ? settings : nil
    }
}
