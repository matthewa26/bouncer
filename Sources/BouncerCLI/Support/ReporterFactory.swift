import Foundation
import BouncerCore
import BouncerReporting

/// Builds the `Reporter` matching a requested output format.
enum ReporterFactory {
    /// Picks a reporter for a format.
    ///
    /// - Parameters:
    ///   - format: The requested output format.
    ///   - repoRoot: The repository root, which the table and HTML reports show paths relative to.
    /// - Returns: The matching reporter.
    static func make(format: OutputFormat, repoRoot: URL) -> Reporter {
        switch format {
        case .console: return ConsoleReporter()
        case .table: return TableReporter(repoRoot: repoRoot)
        case .json: return JSONReporter()
        case .html: return HTMLReporter(repoRoot: repoRoot)
        }
    }
}
