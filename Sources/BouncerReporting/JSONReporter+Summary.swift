import Foundation
import BouncerCore

/// One ranked name in a JSON summary, such as a rule and its finding count.
private struct RankedDTO: Codable {
    /// The rule ID or relative file path.
    let name: String
    /// How many findings it has.
    let count: Int
}

/// The `--summary` JSON shape: the summary's totals and rankings, and no `findings`.
private struct SummaryDTO: Codable {
    /// How many findings the summary covers.
    let findingCount: Int
    /// The finding count for each severity present.
    let bySeverity: [String: Int]
    /// The rules with the most findings.
    let topRules: [RankedDTO]
    /// The files with the most findings, relative to the repository root.
    let topFiles: [RankedDTO]
    /// The dominant-rule hint, or `nil`, and left out, when no rule dominates.
    let hint: String?
    /// How long the run took, or `nil`, and left out, when it wasn't timed.
    let elapsedSeconds: Double?
    /// The measured line coverage, or `nil`, and left out, when coverage wasn't measured.
    let overallLineCoveragePercent: Double?
}

extension JSONReporter {
    /// Renders only a result's summary as JSON: the counts by severity, the top rules and files, the
    /// dominant-rule hint, and the run's time, with no `findings` key.
    ///
    /// - Parameters:
    ///   - result: The analysis result.
    ///   - repoRoot: The repository root, which file paths are shown relative to.
    ///   - elapsed: How long the run took, or `nil` to leave the time out.
    /// - Returns: The rendered JSON.
    public func summary(_ result: AnalysisResult, repoRoot: URL, elapsed: Duration? = nil) -> String {
        let files = result.findings.map { RepoPath.relative($0.filePath, to: repoRoot) }
        return encode(SummaryDTO(
            findingCount: result.findings.count,
            bySeverity: Dictionary(grouping: result.findings, by: \.severity.rawValue).mapValues(\.count),
            topRules: ranked(result.findings.map(\.ruleID)), topFiles: ranked(files),
            hint: ReportSummary.dominantRuleHint(result), elapsedSeconds: elapsed.map(seconds),
            overallLineCoveragePercent: result.coverage?.overallLineCoveragePercent
        ))
    }

    /// Ranks names the way the text summary does.
    ///
    /// - Parameter names: One name per finding.
    /// - Returns: The most frequent names and their counts.
    private func ranked(_ names: [String]) -> [RankedDTO] {
        ReportSummary.top(names).map { RankedDTO(name: $0.name, count: $0.count) }
    }

    /// Converts a duration to fractional seconds.
    ///
    /// - Parameter duration: The duration.
    /// - Returns: Its length in seconds.
    private func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / attosecondsPerSecond
    }
}

/// How many attoseconds make a second, to turn a `Duration`'s parts into seconds.
private let attosecondsPerSecond = 1e18
