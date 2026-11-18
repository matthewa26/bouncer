import Foundation

/// Parses one test-coverage report format into a `CoverageReport`.
///
/// Bouncer never runs a test suite itself; a `CoverageProvider` only reads a
/// report that already exists on disk.
public protocol CoverageProvider: Sendable {
    /// Reports whether this provider recognizes the file at `reportPath`.
    ///
    /// - Parameter reportPath: The candidate report's location.
    /// - Returns: Whether this provider can parse that file.
    func canParse(reportPath: URL) -> Bool

    /// Parses a coverage report into its normalized form.
    ///
    /// - Parameter reportPath: The report's location.
    /// - Returns: The normalized coverage result.
    /// - Throws: If the file can't be read or doesn't match the expected format.
    func parse(reportPath: URL) throws -> CoverageReport
}
