/// Renders an `AnalysisResult` as text for a particular audience.
///
/// `ConsoleReporter` targets a human at a terminal; `JSONReporter` targets a
/// script, CI system, or coding agent.
public protocol Reporter: Sendable {
    /// Renders a result at the requested verbosity.
    ///
    /// - Parameters:
    ///   - result: The analysis result to render.
    ///   - verbosity: How much detail to include.
    /// - Returns: The rendered report, ready to print.
    func report(_ result: AnalysisResult, verbosity: OutputVerbosity) -> String
}
