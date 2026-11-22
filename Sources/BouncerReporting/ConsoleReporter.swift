import Foundation
import BouncerCore

/// Renders an `AnalysisResult` as plain text for a terminal.
public struct ConsoleReporter: Reporter {
    /// How to group findings, or `nil` for one flat line per finding with its full path.
    private let grouping: ReportGrouping?
    /// The repository root, which grouped reports show paths relative to.
    private let repoRoot: URL

    /// Creates a console reporter.
    ///
    /// - Parameters:
    ///   - grouping: How to group findings, or `nil` for one flat line per finding with its full path.
    ///   - repoRoot: The repository root, which grouped reports show paths relative to.
    public init(grouping: ReportGrouping? = nil, repoRoot: URL = URL(fileURLWithPath: "/")) {
        self.grouping = grouping
        self.repoRoot = repoRoot
    }

    /// Renders a result at the requested verbosity.
    ///
    /// - Parameters:
    ///   - result: The analysis result to render.
    ///   - verbosity: How much detail to include.
    /// - Returns: The rendered report.
    public func report(_ result: AnalysisResult, verbosity: OutputVerbosity) -> String {
        switch verbosity {
        case .verbose: return verboseReport(result)
        case .normal: return normalReport(result)
        case .quiet: return quietReport(result)
        case .condensed: return condensedReport(result)
        }
    }

    /// Renders one line per finding, with the message inline.
    ///
    /// - Parameter result: The analysis result to render.
    /// - Returns: The rendered report.
    private func normalReport(_ result: AnalysisResult) -> String {
        guard !result.findings.isEmpty else { return "No findings." }
        if let grouping { return groupedReport(result, by: grouping) }
        return result.findings.map(line).joined(separator: "\n")
    }

    /// Renders one line per finding, plus a trailing blank line for readability.
    ///
    /// - Parameter result: The analysis result to render.
    /// - Returns: The rendered report.
    private func verboseReport(_ result: AnalysisResult) -> String {
        guard !result.findings.isEmpty else { return "No findings." }
        if let grouping { return groupedReport(result, by: grouping) }
        return result.findings.map(line).joined(separator: "\n\n")
    }

    /// Renders only the pass/fail line and a total count.
    ///
    /// - Parameter result: The analysis result to render.
    /// - Returns: The rendered report.
    private func quietReport(_ result: AnalysisResult) -> String {
        result.findings.isEmpty ? "Passed." : "Failed: \(result.findings.count) finding(s)."
    }

    /// Renders a single summary line with a severity breakdown.
    ///
    /// - Parameter result: The analysis result to render.
    /// - Returns: The rendered report.
    private func condensedReport(_ result: AnalysisResult) -> String {
        let errors = result.findings.filter { $0.severity == .error }.count
        let warnings = result.findings.filter { $0.severity == .warning }.count
        let infos = result.findings.filter { $0.severity == .info }.count
        return "\(result.findings.count) finding(s): \(errors) error, \(warnings) warning, \(infos) info."
    }

    /// Renders one finding as a single `path:line: [severity] rule-id message` line.
    ///
    /// - Parameter finding: The finding to render.
    /// - Returns: The rendered line.
    private func line(for finding: Finding) -> String {
        let location = "\(finding.filePath.path):\(finding.line)"
        return "\(location): [\(finding.severity.rawValue)] \(finding.ruleID) - \(finding.message)"
    }

    /// Renders the findings under a header per file or rule, sorted by file, line, and rule, with a blank
    /// line between groups.
    ///
    /// - Parameters:
    ///   - result: The analysis result to render.
    ///   - grouping: Whether to group by file or by rule.
    /// - Returns: The rendered report.
    private func groupedReport(_ result: AnalysisResult, by grouping: ReportGrouping) -> String {
        let findings = FindingSelection.sorted(result.findings, repoRoot: repoRoot)
        let groups = FindingGroup.groups(findings, by: grouping, repoRoot: repoRoot).map { group in
            ([group.header] + group.rows.map { "  " + groupedLine(for: $0, by: grouping) }).joined(separator: "\n")
        }
        return groups.joined(separator: "\n\n")
    }

    /// Renders one finding under its group's header.
    ///
    /// - Parameters:
    ///   - row: The finding.
    ///   - grouping: Whether its header is its file or its rule.
    /// - Returns: `line: [severity] rule-id - message` under a file, or `path:line: [severity] message` under
    ///   a rule.
    private func groupedLine(for row: ReportRow, by grouping: ReportGrouping) -> String {
        switch grouping {
        case .file: return "\(row.line): [\(row.severity)] \(row.ruleID) - \(row.message)"
        case .rule: return "\(row.location): [\(row.severity)] \(row.message)"
        }
    }
}
