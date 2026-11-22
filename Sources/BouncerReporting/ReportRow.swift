import Foundation
import BouncerCore

/// One finding as the table and HTML reports show it, with its path relative to the repo root.
public struct ReportRow: Codable, Sendable, Equatable {
    public let severity: String
    public let ruleID: String
    public let path: String
    public let line: Int
    public let message: String

    /// The finding's location, as `path:line`.
    public var location: String { "\(path):\(line)" }

    /// Builds a row from a finding.
    ///
    /// - Parameters:
    ///   - finding: The finding.
    ///   - repoRoot: The repository root, which the path is shown relative to.
    public init(_ finding: Finding, repoRoot: URL) {
        severity = finding.severity.rawValue
        ruleID = finding.ruleID
        path = RepoPath.relative(finding.filePath, to: repoRoot)
        line = finding.line
        message = finding.message
    }

    /// Builds the rows for a result, most severe first, then by path and line.
    ///
    /// - Parameters:
    ///   - findings: The findings.
    ///   - repoRoot: The repository root.
    /// - Returns: The sorted rows.
    public static func rows(_ findings: [Finding], repoRoot: URL) -> [ReportRow] {
        // Each path is read once up front: `URL.path` inside the comparator dominated sorting millions of findings.
        let keyed = findings.map { (finding: $0, path: $0.filePath.path) }
        let sorted = keyed.sorted { lhs, rhs in
            if lhs.finding.severity != rhs.finding.severity { return lhs.finding.severity > rhs.finding.severity }
            return (lhs.path, lhs.finding.line) < (rhs.path, rhs.finding.line)
        }
        return sorted.map { ReportRow($0.finding, repoRoot: repoRoot) }
    }
}

/// The one-line summary every report ends with: the finding count by severity, and coverage if measured.
public enum ReportSummary {
    /// Summarizes a result.
    ///
    /// - Parameter result: The analysis result.
    /// - Returns: A line such as `12 findings: 2 errors, 9 warnings, 1 info.`
    public static func line(_ result: AnalysisResult) -> String {
        let count = result.findings.count
        guard count > 0 else { return "No findings." + coverage(result) }
        let parts = [Severity.error, .warning, .info].compactMap { severity -> String? in
            let matching = result.findings.filter { $0.severity == severity }.count
            return matching == 0 ? nil : counted(matching, severity)
        }
        return "\(count) finding\(count == 1 ? "" : "s"): \(parts.joined(separator: ", "))." + coverage(result)
    }

    /// Summarizes a result over several lines: the one-line summary, then the rules and files with the most
    /// findings, a hint when one rule dominates, then how long the run took.
    ///
    /// - Parameters:
    ///   - result: The analysis result.
    ///   - repoRoot: The repository root, which file paths are shown relative to.
    ///   - elapsed: How long the run took, or `nil` to leave the time out.
    /// - Returns: The lines, without trailing newlines.
    public static func lines(_ result: AnalysisResult, repoRoot: URL, elapsed: Duration? = nil) -> [String] {
        let files = result.findings.map { RepoPath.relative($0.filePath, to: repoRoot) }
        var lines = [line(result)]
        lines += ranked("Top rules", top(result.findings.map(\.ruleID)))
        lines += ranked("Top files", top(files))
        lines += dominantRuleHint(result).map { [$0] } ?? []
        if let elapsed { lines.append("Finished in \(ProgressText.seconds(elapsed)).") }
        return lines
    }

    /// Counts how often each name occurs and keeps the most frequent, breaking ties alphabetically.
    ///
    /// - Parameters:
    ///   - names: One name per finding, such as its rule ID.
    ///   - limit: How many names to keep.
    /// - Returns: The names and their counts, most frequent first.
    public static func top(_ names: [String], limit: Int = 5) -> [(name: String, count: Int)] {
        let counts = Dictionary(names.map { ($0, 1) }, uniquingKeysWith: +)
        let sorted = counts.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }
        return sorted.prefix(limit).map { (name: $0.key, count: $0.value) }
    }

    /// Suggests setting aside a rule that has more than half of all findings, so the rest can be seen.
    ///
    /// - Parameter result: The analysis result.
    /// - Returns: A line such as `duplicate-block is 58% of findings; disable it or baseline it to focus on the
    ///   rest.`, or `nil` when no rule has more than half, or every finding is from that one rule.
    public static func dominantRuleHint(_ result: AnalysisResult) -> String? {
        let total = result.findings.count
        guard let leader = top(result.findings.map(\.ruleID), limit: 1).first,
              leader.count * 2 > total, leader.count < total else { return nil }
        let percent = Int((Double(leader.count) * percentScale / Double(total)).rounded())
        return "\(leader.name) is \(percent)% of findings; disable it or baseline it to focus on the rest."
    }

    /// What a fraction is multiplied by to give a percentage.
    private static let percentScale = 100.0

    /// Lists ranked names under a heading, with their counts right-aligned.
    ///
    /// - Parameters:
    ///   - title: The heading, such as `Top rules`.
    ///   - entries: The ranked names.
    /// - Returns: The heading and one indented line per name, or nothing when there are none.
    private static func ranked(_ title: String, _ entries: [(name: String, count: Int)]) -> [String] {
        guard !entries.isEmpty else { return [] }
        let width = String(entries.map(\.count).max() ?? 0).count
        let rows = entries.map { entry in
            "  " + String(repeating: " ", count: width - String(entry.count).count) + "\(entry.count)  \(entry.name)"
        }
        return ["\(title):"] + rows
    }

    /// Names a count of one severity, such as `2 errors` or `1 info`.
    ///
    /// - Parameters:
    ///   - count: How many findings have the severity.
    ///   - severity: The severity.
    /// - Returns: The count and name, plural where English needs it.
    private static func counted(_ count: Int, _ severity: Severity) -> String {
        let plural = count != 1 && severity != .info
        return "\(count) \(severity.rawValue)\(plural ? "s" : "")"
    }

        /// Describes the measured line coverage.
    ///
    /// - Parameter result: The analysis result.
    /// - Returns: ` Line coverage: 81.2%.`, or an empty string if coverage wasn't measured.
    private static func coverage(_ result: AnalysisResult) -> String {
        result.coverage.map { String(format: " Line coverage: %.1f%%.", $0.overallLineCoveragePercent) } ?? ""
    }
}
