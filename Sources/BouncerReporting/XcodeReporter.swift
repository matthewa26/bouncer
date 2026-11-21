import Foundation
import BouncerCore

/// Renders an `AnalysisResult` in the diagnostic grammar Xcode reads from build-phase output, so each finding
/// shows inline in the editor and in the Issue navigator.
///
/// Each finding becomes `/absolute/path:LINE:1: error|warning|note: message [rule-id]`, and the report ends
/// with the run's one-line summary as a plain line. Every verbosity prints every finding, since Xcode needs
/// each one to place it.
public struct XcodeReporter: Reporter {
    /// Creates an Xcode reporter.
    public init() {}

    /// Renders a result as one Xcode diagnostic per finding, then the summary line.
    ///
    /// - Parameters:
    ///   - result: The analysis result to render.
    ///   - verbosity: Ignored: Xcode needs every finding to place it.
    /// - Returns: The rendered report.
    public func report(_ result: AnalysisResult, verbosity: OutputVerbosity) -> String {
        (result.findings.map(Self.diagnostic) + [ReportSummary.line(result)]).joined(separator: "\n")
    }

    /// Renders one finding as an Xcode diagnostic line.
    ///
    /// - Parameter finding: The finding to render.
    /// - Returns: A line such as `/repo/a.swift:3:1: warning: Function is too long. [long-function]`.
    static func diagnostic(_ finding: Finding) -> String {
        let path = finding.filePath.absoluteURL.standardizedFileURL.path
        let message = finding.message.replacingOccurrences(of: "\n", with: " ")
        return "\(path):\(max(finding.line, 1)):1: \(kind(finding.severity)): \(message) [\(finding.ruleID)]"
    }

    /// Names the Xcode diagnostic kind for a severity.
    ///
    /// - Parameter severity: The finding's severity.
    /// - Returns: `error`, `warning`, or `note` for `info`.
    static func kind(_ severity: Severity) -> String {
        switch severity {
        case .error: return "error"
        case .warning: return "warning"
        case .info: return "note"
        }
    }
}
