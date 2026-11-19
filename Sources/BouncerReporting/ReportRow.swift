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
        let sorted = findings.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return (lhs.filePath.path, lhs.line) < (rhs.filePath.path, rhs.line)
        }
        return sorted.map { ReportRow($0, repoRoot: repoRoot) }
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
