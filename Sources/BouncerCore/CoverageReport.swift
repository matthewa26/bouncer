/// A normalized test-coverage result, regardless of which report format produced it.
///
/// `LCOVCoverageProvider` and `XccovCoverageProvider` both parse into this
/// same shape, so `AnalysisEngine`'s threshold check never branches on which
/// coverage format was actually read.
public struct CoverageReport: Sendable, Equatable {
    /// The percentage of lines covered across the whole report, from 0 to 100.
    public let overallLineCoveragePercent: Double

    /// Creates a coverage report.
    ///
    /// - Parameter overallLineCoveragePercent: The percentage of lines covered, from 0 to 100.
    public init(overallLineCoveragePercent: Double) {
        self.overallLineCoveragePercent = overallLineCoveragePercent
    }
}
