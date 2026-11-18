import Foundation
import BouncerCore

/// Flags a file whose density of TODO/FIXME/HACK markers exceeds a configured ratio.
public struct TodoDensityRule: Rule {
    public static let ruleID = "todo-density"
    public let id = TodoDensityRule.ruleID
    private static let markerPattern = try? NSRegularExpression(pattern: "TODO|FIXME|HACK")

    /// Creates the rule. Marker detection is language-agnostic, so no profile is needed.
    public init() {}

    /// Flags the file once if its marker density exceeds `maxPerHundredLines`.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's `maxPerHundredLines` parameter.
    /// - Returns: A single finding, or none.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, !file.lines.isEmpty, let regex = Self.markerPattern else { return [] }
        let markerCount = file.lines.filter { containsMarker($0, regex: regex) }.count
        let perHundred = Double(markerCount) / Double(file.lines.count) * 100
        let maxPerHundred = settings.parameters.int("maxPerHundredLines", default: 5)
        guard perHundred > Double(maxPerHundred) else { return [] }
        let message = "\(markerCount) TODO/FIXME/HACK markers across \(file.lines.count) lines."
        return [Finding(ruleID: id, severity: settings.severity, filePath: file.path, line: 1, message: message)]
    }

    /// Checks a single line for a TODO/FIXME/HACK marker.
    ///
    /// - Parameters:
    ///   - line: The line to check.
    ///   - regex: The compiled marker pattern.
    /// - Returns: Whether the line contains a marker.
    private func containsMarker(_ line: Substring, regex: NSRegularExpression) -> Bool {
        let text = String(line)
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
