import Foundation
import BouncerCore

/// Naming rules over declared variables and parameters, and the duplicated-string rule.
extension DeclarationFindings {
    private static let conventionalShortNames: Set<String> = [
        "_", "i", "j", "k", "x", "y", "z", "e", "n", "t", "id", "ok"
    ]
    private static let negatedPattern = try? NSRegularExpression(
        pattern: "^(is|has|should|can|did|was|will)(Not|No)(?=[A-Z])|^not(?=[A-Z])"
    )
    private static let hungarianPattern = try? NSRegularExpression(
        pattern: "^(str|sz|int|bool|arr|lst|obj|fn|dbl|flt)(?=[A-Z])|^b(?=[A-Z][a-z])|^m_"
    )

    /// A naming rule that flags names matching a pattern.
    private struct NamePatternRule {
        let pattern: NSRegularExpression?
        let ruleID: String
        let problem: String
    }

    /// Runs every naming rule and the duplicated-string rule.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including each rule's resolved settings.
    /// - Returns: The combined findings.
    static func nameFindings(_ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext) -> [Finding] {
        let negated = NamePatternRule(
            pattern: negatedPattern, ruleID: "negated-boolean-name", problem: "is negated; name the positive case"
        )
        let hungarian = NamePatternRule(
            pattern: hungarianPattern, ruleID: "hungarian-notation", problem: "encodes its type; drop the prefix"
        )
        return shortIdentifiers(summary, file: file, context: context)
            + [negated, hungarian].flatMap { namesMatching($0, summary, file: file, context: context) }
            + duplicatedStrings(summary, file: file, context: context)
    }

    /// Flags variables and parameters whose names are too short to say what they hold.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's `minLength` parameter.
    /// - Returns: One finding per short name, skipping conventional ones like `i` and `x`.
    private static func shortIdentifiers(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: "short-identifier")
        guard settings.enabled else { return [] }
        let minLength = settings.parameters.int("minLength", default: 2)
        return summary.declaredNames.filter { $0.name.count < minLength && !isConventional($0.name) }.map {
            let message = "Name \"\($0.name)\" is too short to say what it holds."
            return finding("short-identifier", $0.line, message, settings.severity, file)
        }
    }

    /// Reports whether a short name is conventional enough to allow, such as a loop index or `x`.
    ///
    /// - Parameter name: The name.
    /// - Returns: Whether it's in the conventional set.
    private static func isConventional(_ name: String) -> Bool {
        conventionalShortNames.contains(name)
    }

    /// Flags declared names matching a naming rule's pattern.
    ///
    /// - Parameters:
    ///   - rule: The rule, its pattern, and what's wrong with a match.
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per matching name.
    private static func namesMatching(
        _ rule: NamePatternRule, _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: rule.ruleID)
        guard settings.enabled, let pattern = rule.pattern else { return [] }
        let matching = summary.declaredNames.filter {
            pattern.firstMatch(in: $0.name, range: NSRange($0.name.startIndex..., in: $0.name)) != nil
        }
        return matching.map {
            finding(rule.ruleID, $0.line, "Name \"\($0.name)\" \(rule.problem).", settings.severity, file)
        }
    }

    /// Flags string literals repeated often enough to deserve a named constant, once each at first use.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's `minOccurrences` and `minLength` parameters.
    /// - Returns: One finding per repeated literal.
    private static func duplicatedStrings(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: "duplicated-string-literal")
        guard settings.enabled else { return [] }
        return repeatedStrings(summary, settings: settings).map { first, count in
            let message = "String \"\(first.text)\" appears \(count) times; name it with a constant."
            return finding("duplicated-string-literal", first.line, message, settings.severity, file)
        }
    }

    /// Groups a file's string literals, keeping each repeated one's first occurrence and count.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - settings: The rule's settings, for `minOccurrences` and `minLength`.
    /// - Returns: Each repeated literal's first occurrence and count, in source order, then by text when two start
    ///   on the same line, so the order never depends on dictionary iteration.
    private static func repeatedStrings(
        _ summary: DeclarationSummary, settings: RuleSettings
    ) -> [(first: CollectedString, count: Int)] {
        let minOccurrences = settings.parameters.int("minOccurrences", default: 3)
        let minLength = settings.parameters.int("minLength", default: 5)
        let groups = Dictionary(grouping: summary.stringLiterals.filter { $0.text.count >= minLength }, by: \.text)
        return groups.values.filter { $0.count >= minOccurrences }
            .compactMap { group in group.min { $0.line < $1.line }.map { ($0, group.count) } }
            .sorted { ($0.first.line, $0.first.text) < ($1.first.line, $1.first.text) }
    }
}
