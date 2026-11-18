/// The `coverage` section of `.bouncer`.
public struct CoverageConfig: Codable, Sendable, Equatable {
    public var enabled: Bool?
    public var format: String?
    public var reportPath: String?
    public var threshold: Double?
    public var failOnMissingReport: Bool?

    /// Creates a coverage config.
    ///
    /// - Parameters:
    ///   - enabled: Whether coverage checking is turned on.
    ///   - format: `"xccov"`, `"lcov"`, or `"auto"`.
    ///   - reportPath: The coverage report's location, relative to the repo root.
    ///   - threshold: The minimum acceptable line coverage percentage.
    ///   - failOnMissingReport: Whether a missing report is an error rather than a warning.
    public init(
        enabled: Bool? = nil, format: String? = nil, reportPath: String? = nil,
        threshold: Double? = nil, failOnMissingReport: Bool? = nil
    ) {
        self.enabled = enabled
        self.format = format
        self.reportPath = reportPath
        self.threshold = threshold
        self.failOnMissingReport = failOnMissingReport
    }

    /// Merges another config's fields over this one's, preferring the other's when both are set.
    ///
    /// - Parameter other: The config whose fields take precedence.
    /// - Returns: The merged config.
    public func merging(_ other: CoverageConfig) -> CoverageConfig {
        CoverageConfig(
            enabled: other.enabled ?? enabled,
            format: other.format ?? format,
            reportPath: other.reportPath ?? reportPath,
            threshold: other.threshold ?? threshold,
            failOnMissingReport: other.failOnMissingReport ?? failOnMissingReport
        )
    }
}
