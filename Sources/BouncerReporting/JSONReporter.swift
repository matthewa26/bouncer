import Foundation
import BouncerCore

/// A JSON-encodable mirror of `Finding`, since `Finding` itself isn't `Codable`.
private struct FindingDTO: Codable {
    let ruleID: String
    let severity: String
    let filePath: String
    let line: Int
    let message: String
    /// The finding's OWASP Top 10 category (`"A05:2025"`), or `nil`, and left out of the JSON, for a rule that
    /// isn't mapped to one, so untagged findings serialize exactly as they did before tagging existed.
    let owasp: String?

    /// Creates a DTO from a finding.
    ///
    /// - Parameter finding: The finding to mirror.
    init(_ finding: Finding) {
        ruleID = finding.ruleID
        severity = finding.severity.rawValue
        filePath = finding.filePath.path
        line = finding.line
        message = finding.message
        owasp = OWASPCategory.category(forRule: finding.ruleID)?.rawValue
    }
}

/// The full JSON shape emitted at every verbosity except `.condensed`.
private struct FullReportDTO: Codable {
    let findings: [FindingDTO]
    let overallLineCoveragePercent: Double?
}

/// The condensed JSON shape: a violation count and its breakdown by severity.
private struct CondensedReportDTO: Codable {
    let violationCount: Int
    let bySeverity: [String: Int]
}

/// Renders an `AnalysisResult` as JSON, for CI systems and coding agents.
public struct JSONReporter: Reporter {
    /// Creates a JSON reporter.
    public init() {}

    /// Renders a result as JSON.
    ///
    /// Every verbosity except `.condensed` emits the complete structured
    /// findings, since machine consumers want completeness rather than a
    /// trimmed-down summary.
    ///
    /// - Parameters:
    ///   - result: The analysis result to render.
    ///   - verbosity: `.condensed` for a summary; anything else for full detail.
    /// - Returns: The rendered JSON.
    public func report(_ result: AnalysisResult, verbosity: OutputVerbosity) -> String {
        let dto: any Encodable = verbosity == .condensed ? condensedDTO(result) : fullDTO(result)
        return encode(dto)
    }

    /// Builds the full-detail DTO for a result.
    ///
    /// - Parameter result: The analysis result to convert.
    /// - Returns: The full report DTO.
    private func fullDTO(_ result: AnalysisResult) -> FullReportDTO {
        FullReportDTO(
            findings: result.findings.map(FindingDTO.init),
            overallLineCoveragePercent: result.coverage?.overallLineCoveragePercent
        )
    }

    /// Builds the condensed summary DTO for a result.
    ///
    /// - Parameter result: The analysis result to convert.
    /// - Returns: The condensed report DTO.
    private func condensedDTO(_ result: AnalysisResult) -> CondensedReportDTO {
        let bySeverity = Dictionary(grouping: result.findings, by: \.severity.rawValue).mapValues(\.count)
        return CondensedReportDTO(violationCount: result.findings.count, bySeverity: bySeverity)
    }

    /// Encodes a value as pretty-printed JSON, falling back to `"{}"` on failure.
    ///
    /// - Parameter value: The value to encode.
    /// - Returns: The encoded JSON string.
    func encode(_ value: any Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
