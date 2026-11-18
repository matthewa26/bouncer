#if os(macOS)
import Foundation
import BouncerCore

/// Parses Xcode's `.xcresult` coverage data via `xcrun xccov`.
///
/// Compiled only on macOS, since `xcrun` doesn't exist anywhere else - on
/// Linux and Windows, `format: auto` only ever resolves to LCOV.
public struct XccovCoverageProvider: CoverageProvider {
    private struct XccovReport: Decodable {
        let lineCoverage: Double
    }

    /// Creates an xccov provider.
    public init() {}

    /// Recognizes `.xcresult` bundles.
    ///
    /// - Parameter reportPath: The candidate report's location.
    /// - Returns: Whether the path is an `.xcresult` bundle.
    public func canParse(reportPath: URL) -> Bool {
        reportPath.pathExtension.lowercased() == "xcresult"
    }

    /// Parses an `.xcresult` bundle's overall line coverage via `xcrun xccov`.
    ///
    /// - Parameter reportPath: The `.xcresult` bundle's location.
    /// - Returns: The normalized coverage result.
    /// - Throws: If `xccov` fails or its output can't be decoded.
    public func parse(reportPath: URL) throws -> CoverageReport {
        let data = try runXccov(on: reportPath)
        let report = try JSONDecoder().decode(XccovReport.self, from: data)
        return CoverageReport(overallLineCoveragePercent: report.lineCoverage * 100)
    }

    /// Runs `xcrun xccov view --report --json` and captures its output.
    ///
    /// - Parameter reportPath: The `.xcresult` bundle's location.
    /// - Returns: The command's standard output.
    /// - Throws: If the process can't be launched or exits with an error.
    private func runXccov(on reportPath: URL) throws -> Data {
        let pipe = Pipe()
        let process = xccovProcess(reportPath: reportPath, output: pipe)
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    /// Builds the `xcrun xccov view --report --json` process, without running it.
    ///
    /// - Parameters:
    ///   - reportPath: The `.xcresult` bundle's location.
    ///   - output: The pipe to capture standard output into.
    /// - Returns: The configured, unstarted process.
    private func xccovProcess(reportPath: URL, output: Pipe) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xccov", "view", "--report", "--json", reportPath.path]
        process.standardOutput = output
        return process
    }
}
#endif
