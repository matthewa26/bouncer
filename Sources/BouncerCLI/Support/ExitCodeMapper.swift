import BouncerCore

/// Maps an analysis result to the process exit code a subcommand should return.
enum ExitCodeMapper {
    /// Computes the exit code for a result against a severity threshold.
    ///
    /// - Parameters:
    ///   - result: The analysis result.
    ///   - threshold: The minimum severity that should cause a non-zero exit.
    /// - Returns: `1` if any finding meets or exceeds `threshold`, otherwise `0`.
    static func exitCode(for result: AnalysisResult, threshold: Severity) -> Int32 {
        result.findings.contains { $0.severity >= threshold } ? 1 : 0
    }
}
