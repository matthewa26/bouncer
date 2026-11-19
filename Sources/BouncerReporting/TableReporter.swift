import Foundation
import BouncerCore

/// Renders an `AnalysisResult` as an aligned Markdown table, readable in a terminal and ready to paste into
/// an issue, a pull request, or an AI chat.
public struct TableReporter: Reporter {
    private static let headers = ["Severity", "Rule", "Location", "Message"]
    private let repoRoot: URL

    /// Creates a table reporter.
    ///
    /// - Parameter repoRoot: The repository root, which locations are shown relative to.
    public init(repoRoot: URL) {
        self.repoRoot = repoRoot
    }

    /// Renders a result as a table of findings, most severe first, followed by a summary line.
    ///
    /// - Parameters:
    ///   - result: The analysis result to render.
    ///   - verbosity: `.condensed` for the summary line alone; anything else for the full table.
    /// - Returns: The rendered report.
    public func report(_ result: AnalysisResult, verbosity: OutputVerbosity) -> String {
        let summary = ReportSummary.line(result)
        guard verbosity != .condensed, !result.findings.isEmpty else { return summary }
        let rows = ReportRow.rows(result.findings, repoRoot: repoRoot).map {
            [$0.severity, $0.ruleID, $0.location, $0.message]
        }
        return Self.table([Self.headers] + rows) + "\n\n" + summary
    }

    /// Lays out rows as a Markdown table with every column padded to its widest cell.
    ///
    /// - Parameter rows: The header row, then the data rows.
    /// - Returns: The table.
    static func table(_ rows: [[String]]) -> String {
        let cells = rows.map { $0.map(escape) }
        let widths = headers.indices.map { column in cells.map { $0[column].count }.max() ?? 0 }
        let lines = cells.map { line($0, widths: widths) }
        let divider = line(widths.map { String(repeating: "-", count: $0) }, widths: widths)
        return ([lines[0], divider] + lines.dropFirst()).joined(separator: "\n")
    }

    /// Formats one table row.
    ///
    /// - Parameters:
    ///   - cells: The row's cells.
    ///   - widths: Each column's width.
    /// - Returns: The row, such as `| error | long-lines | a.swift:3 | … |`.
    private static func line(_ cells: [String], widths: [Int]) -> String {
        let padded = zip(cells, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }
        return "| " + padded.joined(separator: " | ") + " |"
    }

    /// Keeps a cell on one line and its pipes from splitting the column.
    ///
    /// - Parameter cell: The cell's text.
    /// - Returns: The escaped text.
    private static func escape(_ cell: String) -> String {
        cell.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "\\|")
    }
}
