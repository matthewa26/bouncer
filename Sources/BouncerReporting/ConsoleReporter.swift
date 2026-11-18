import BouncerCore

/// Renders an `AnalysisResult` as plain text for a terminal.
public struct ConsoleReporter: Reporter {
    /// Creates a console reporter.
    public init() {}

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
        return result.findings.map(line).joined(separator: "\n")
    }

    /// Renders one line per finding, plus a trailing blank line for readability.
    ///
    /// - Parameter result: The analysis result to render.
    /// - Returns: The rendered report.
    private func verboseReport(_ result: AnalysisResult) -> String {
        guard !result.findings.isEmpty else { return "No findings." }
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
}
