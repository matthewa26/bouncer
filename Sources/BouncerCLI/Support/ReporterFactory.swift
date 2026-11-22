import Foundation
import BouncerCore
import BouncerReporting

/// Builds the `Reporter` matching a requested output format.
enum ReporterFactory {
    /// Picks a reporter for a format.
    ///
    /// - Parameters:
    ///   - format: The requested output format.
    ///   - repoRoot: The repository root, which the table, HTML, agent, and grouped console reports show paths
    ///     relative to.
    ///   - grouping: The `--group-by` choice, or `nil` for each format's default.
    ///   - selection: The filtered and paged findings the report shows, for the agent footer.
    /// - Returns: The matching reporter.
    static func make(
        format: OutputFormat, repoRoot: URL, grouping: ReportGrouping? = nil, selection: SelectedFindings? = nil
    ) -> Reporter {
        switch format {
        case .console: ConsoleReporter(grouping: grouping, repoRoot: repoRoot)
        case .table: TableReporter(repoRoot: repoRoot)
        case .json: JSONReporter()
        case .html: HTMLReporter(repoRoot: repoRoot)
        case .xcode: XcodeReporter()
        case .agent: AgentReporter(repoRoot: repoRoot, grouping: grouping ?? .file, selection: selection)
        }
    }
}
