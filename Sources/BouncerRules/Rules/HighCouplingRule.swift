import Foundation
import BouncerCore

/// Flags a file that imports more distinct modules than a configured threshold.
///
/// A coarse afferent-coupling proxy: it counts import-style lines, not actual
/// symbol usage or a real dependency graph. A real cross-file coupling metric
/// is out of scope for the per-file rule model this rule lives in.
public struct HighCouplingRule: Rule {
    public static let ruleID = "high-coupling"
    public let id = HighCouplingRule.ruleID
    private let profile: LanguageProfile

    /// Creates the rule for a specific language's import syntax.
    ///
    /// - Parameter profile: The language profile providing the import-line pattern.
    public init(profile: LanguageProfile) {
        self.profile = profile
    }

    /// Flags the file once if its import count exceeds `maxImports`.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's `maxImports` parameter.
    /// - Returns: A single finding, or none.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, let pattern = profile.importLinePattern,
              let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let maxImports = settings.parameters.int("maxImports", default: 15)
        let count = file.lines.filter { matches($0, regex: regex) }.count
        guard count > maxImports else { return [] }
        let message = "File imports \(count) modules, over the \(maxImports)-import coupling threshold."
        return [Finding(ruleID: id, severity: settings.severity, filePath: file.path, line: 1, message: message)]
    }

    /// Tests whether a line matches the import pattern.
    ///
    /// - Parameters:
    ///   - line: The line to test.
    ///   - regex: The compiled import-line pattern.
    /// - Returns: Whether the line is an import statement.
    private func matches(_ line: Substring, regex: NSRegularExpression) -> Bool {
        let text = String(line)
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
