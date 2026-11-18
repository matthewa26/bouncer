import Foundation
import BouncerCore

/// Flags a declaration whose identifier doesn't match its language's naming convention.
public struct NamingConventionRule: Rule {
    public static let ruleID = "naming-convention"
    public let id = NamingConventionRule.ruleID
    private let profile: LanguageProfile

    /// Creates the rule for a specific language's naming conventions.
    ///
    /// - Parameter profile: The language profile providing the naming rules to check.
    public init(profile: LanguageProfile) {
        self.profile = profile
    }

    /// Flags every declaration whose identifier fails its expected naming pattern.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per badly-named declaration.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled else { return [] }
        return profile.namingRules.flatMap { rule in
            findings(for: rule, in: file, severity: settings.severity)
        }
    }

    /// Checks every line against one naming rule.
    ///
    /// - Parameters:
    ///   - rule: The naming rule to check.
    ///   - file: The file to scan.
    ///   - severity: The severity to report at.
    /// - Returns: One finding per line whose declared identifier fails the rule.
    private func findings(for rule: NamingRule, in file: SourceFile, severity: Severity) -> [Finding] {
        guard let declRegex = try? NSRegularExpression(pattern: rule.declarationPattern),
              let expectedRegex = try? NSRegularExpression(pattern: rule.expectedIdentifierPattern) else { return [] }
        return file.lines.enumerated().compactMap { index, line in
            finding(
                forLine: line, index: index, file: file, rule: rule,
                declRegex: declRegex, expectedRegex: expectedRegex, severity: severity
            )
        }
    }

    /// Builds a finding for one line if it declares a badly-named identifier.
    ///
    /// - Parameters:
    ///   - line: The line's text.
    ///   - index: The line's 0-indexed position.
    ///   - file: The file being analyzed.
    ///   - rule: The naming rule being checked.
    ///   - declRegex: The compiled declaration pattern.
    ///   - expectedRegex: The compiled expected-identifier pattern.
    ///   - severity: The severity to report at.
    /// - Returns: A finding, or `nil` if the line doesn't declare a badly-named identifier.
    private func finding(
        forLine line: Substring, index: Int, file: SourceFile, rule: NamingRule,
        declRegex: NSRegularExpression, expectedRegex: NSRegularExpression, severity: Severity
    ) -> Finding? {
        guard let identifier = capturedIdentifier(in: String(line), using: declRegex) else { return nil }
        guard !matches(identifier, expectedRegex) else { return nil }
        let message = "\(rule.kindLabel) \"\(identifier)\" doesn't match the expected naming convention."
        return Finding(ruleID: id, severity: severity, filePath: file.path, line: index + 1, message: message)
    }

    /// Extracts a declaration pattern's first capture group from a line.
    ///
    /// - Parameters:
    ///   - text: The line's text.
    ///   - regex: The compiled declaration pattern, whose first group captures the identifier.
    /// - Returns: The captured identifier, or `nil` if the pattern didn't match.
    private func capturedIdentifier(in text: String, using regex: NSRegularExpression) -> String? {
        let fullRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: fullRange), match.numberOfRanges > 1 else { return nil }
        guard let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// Tests whether a string matches a compiled pattern anywhere.
    ///
    /// - Parameters:
    ///   - text: The string to test.
    ///   - regex: The compiled pattern.
    /// - Returns: Whether the pattern matches.
    private func matches(_ text: String, _ regex: NSRegularExpression) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
