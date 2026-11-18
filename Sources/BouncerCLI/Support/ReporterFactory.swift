import BouncerCore
import BouncerReporting

/// Builds the `Reporter` matching a requested output format.
enum ReporterFactory {
    /// Picks a reporter for a format.
    ///
    /// - Parameter format: The requested output format.
    /// - Returns: A console or JSON reporter.
    static func make(format: OutputFormat) -> Reporter {
        switch format {
        case .console: return ConsoleReporter()
        case .json: return JSONReporter()
        }
    }
}
