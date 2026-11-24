import Foundation
import BouncerCore

/// A `Rule` that flags any line matching a regular expression.
///
/// Backs both per-language extra checks and user-declared `customRules`, so
/// adding a new pattern-based check never requires a new Swift type.
public struct PatternRule: Rule {
    public let id: String
    private let regex: NSRegularExpression
    private let message: String
    /// Exempts a whole file when it matches anywhere, or `nil` to check every file.
    private let exemptFile: NSRegularExpression?

    /// Creates a pattern rule, or returns `nil` if a pattern doesn't compile.
    ///
    /// - Parameter spec: The rule's identifier, patterns, and message.
    public init?(spec: PatternRuleSpec) {
        let exemptFile = spec.exemptFilePattern.flatMap {
            try? NSRegularExpression(pattern: $0, options: .anchorsMatchLines)
        }
        guard let regex = try? NSRegularExpression(pattern: spec.pattern),
              (exemptFile == nil) == (spec.exemptFilePattern == nil) else { return nil }
        self.id = spec.id
        self.regex = regex
        self.message = spec.message
        self.exemptFile = exemptFile
    }

    /// Flags every line that contains a match for this rule's pattern, unless the file is exempt.
    ///
    /// - Parameters:
    ///   - file: The file to inspect.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per matching line.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, !isExempt(file) else { return [] }
        return file.lines.enumerated().compactMap { index, line in
            finding(forLine: line, index: index, file: file, severity: settings.severity)
        }
    }

    /// Reports whether a file matches the exemption pattern.
    ///
    /// - Parameter file: The file.
    /// - Returns: Whether the rule skips it.
    private func isExempt(_ file: SourceFile) -> Bool {
        guard let exemptFile else { return false }
        return exemptFile.firstMatch(in: file.contents, range: NSRange(file.contents.startIndex..., in: file.contents))
            != nil
    }

    /// Builds a finding for one line if it matches this rule's pattern.
    ///
    /// - Parameters:
    ///   - line: The line's text.
    ///   - index: The line's 0-indexed position in the file.
    ///   - file: The file being analyzed, used for the finding's path.
    ///   - severity: The severity to report matches at.
    /// - Returns: A finding, or `nil` if the line doesn't match.
    private func finding(forLine line: Substring, index: Int, file: SourceFile, severity: Severity) -> Finding? {
        let text = String(line)
        guard regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil else { return nil }
        return Finding(ruleID: id, severity: severity, filePath: file.path, line: index + 1, message: message)
    }
}
