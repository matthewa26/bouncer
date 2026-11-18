import Foundation

/// Turns a coverage report and a configured threshold into a `Finding`.
///
/// Keeping this as a pure function lets a below-threshold result flow through
/// the exact same reporting, baseline, and exit-code path as every other
/// finding, instead of needing special-cased handling elsewhere.
public enum CoverageThresholdChecker {
    /// The synthetic rule identifier used for threshold findings.
    public static let ruleID = "coverage-threshold"

    /// Checks a coverage report against a threshold.
    ///
    /// - Parameters:
    ///   - report: The parsed coverage report.
    ///   - threshold: The minimum acceptable line coverage percentage.
    ///   - repoRoot: The repository root, used as the finding's file path.
    /// - Returns: A finding if coverage is below the threshold, otherwise `nil`.
    public static func evaluate(report: CoverageReport, threshold: Double, repoRoot: URL) -> Finding? {
        guard report.overallLineCoveragePercent < threshold else { return nil }
        let message = "Coverage is \(report.overallLineCoveragePercent)%, below the \(threshold)% threshold."
        return Finding(ruleID: ruleID, severity: .error, filePath: repoRoot, line: 0, message: message)
    }
}
