import Foundation
import BouncerCore

/// Parses an LCOV `.info` coverage report.
///
/// LCOV is plain text and needs no external dependency to parse, which is
/// what makes it the one coverage format available on every platform Bouncer
/// runs on.
public struct LCOVCoverageProvider: CoverageProvider {
    /// Creates an LCOV provider.
    public init() {}

    /// Recognizes `.info`/`.lcov` files by extension.
    ///
    /// - Parameter reportPath: The candidate report's location.
    /// - Returns: Whether the extension matches LCOV's conventional names.
    public func canParse(reportPath: URL) -> Bool {
        ["info", "lcov"].contains(reportPath.pathExtension.lowercased())
    }

    /// Parses an LCOV report into overall line coverage.
    ///
    /// - Parameter reportPath: The report's location.
    /// - Returns: The normalized coverage result.
    /// - Throws: If the file can't be read.
    public func parse(reportPath: URL) throws -> CoverageReport {
        let contents = try String(contentsOf: reportPath, encoding: .utf8)
        var linesFound = 0
        var linesHit = 0
        accumulate(contents: contents, linesFound: &linesFound, linesHit: &linesHit)
        let percent = linesFound > 0 ? Double(linesHit) / Double(linesFound) * 100 : 0
        return CoverageReport(overallLineCoveragePercent: percent)
    }

    /// Sums the `LF:`/`LH:` totals across every record in an LCOV file.
    ///
    /// - Parameters:
    ///   - contents: The LCOV file's full text.
    ///   - linesFound: Accumulates the total instrumented line count.
    ///   - linesHit: Accumulates the total covered line count.
    private func accumulate(contents: String, linesFound: inout Int, linesHit: inout Int) {
        for line in contents.split(separator: "\n") {
            if let value = intValue(after: "LF:", in: line) { linesFound += value }
            if let value = intValue(after: "LH:", in: line) { linesHit += value }
        }
    }

    /// Extracts the integer following a known LCOV key on one line.
    ///
    /// - Parameters:
    ///   - prefix: The key to match, such as `"LF:"`.
    ///   - line: The line to check.
    /// - Returns: The parsed integer, or `nil` if the line doesn't start with `prefix`.
    private func intValue(after prefix: String, in line: Substring) -> Int? {
        guard line.hasPrefix(prefix) else { return nil }
        return Int(line.dropFirst(prefix.count))
    }
}
