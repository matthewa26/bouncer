import Foundation
import BouncerCore

/// Flags lines that look like a hardcoded credential.
///
/// This is a small, deliberately narrow set of patterns for catching obvious
/// mistakes, not a secrets-scanner replacement - a dedicated tool such as
/// gitleaks or trufflehog should be used for real secret-scanning coverage.
public struct SecretPatternRule: Rule {
    public static let ruleID = "secret-looking-pattern"
    public let id = SecretPatternRule.ruleID
    private static let patterns: [NSRegularExpression] = [
        "AKIA[0-9A-Z]{16}",
        "-----BEGIN (RSA |EC )?PRIVATE KEY-----",
        "(?i)(api[_-]?key|secret|password)\\s*[:=]\\s*[\"'][A-Za-z0-9+/=_-]{8,}[\"']"
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    /// Creates the rule. Secret shapes are language-agnostic, so no profile is needed.
    public init() {}

    /// Flags every line matching one of the bundled secret-like patterns.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per matching line.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled else { return [] }
        return file.lines.enumerated().compactMap { index, line in
            guard matchesAnyPattern(line) else { return nil }
            let message = "Line looks like it contains a hardcoded credential."
            return Finding(
                ruleID: id, severity: settings.severity, filePath: file.path, line: index + 1, message: message
            )
        }
    }

    /// Checks a line against every bundled pattern.
    ///
    /// - Parameter line: The line to check.
    /// - Returns: Whether any pattern matches.
    private func matchesAnyPattern(_ line: Substring) -> Bool {
        let text = String(line)
        let range = NSRange(text.startIndex..., in: text)
        return Self.patterns.contains { $0.firstMatch(in: text, range: range) != nil }
    }
}
