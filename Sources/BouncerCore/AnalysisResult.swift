/// Everything an `AnalysisEngine` run produced, ready for a `Reporter`.
public struct AnalysisResult: Sendable {
    /// Every finding, already filtered against the baseline if one was loaded.
    public let findings: [Finding]

    /// The parsed coverage report, if coverage checking was requested.
    public let coverage: CoverageReport?

    /// Creates an analysis result.
    ///
    /// - Parameters:
    ///   - findings: Every finding, already filtered against the baseline.
    ///   - coverage: The parsed coverage report, if coverage checking ran.
    public init(findings: [Finding], coverage: CoverageReport?) {
        self.findings = findings
        self.coverage = coverage
    }

    /// The highest severity among all findings, if there are any.
    public var highestSeverity: Severity? {
        findings.map(\.severity).max()
    }
}
