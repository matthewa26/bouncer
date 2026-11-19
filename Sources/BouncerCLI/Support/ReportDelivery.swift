import Foundation
import BouncerReporting

/// Sends a rendered report where it belongs: printed to the terminal, or written to a file with a note of
/// where it is and how to open it.
enum ReportDelivery {
    /// Prints the report, or writes it to `--output` (or, for HTML, the default report file) and prints its
    /// location and the run's summary.
    ///
    /// - Parameters:
    ///   - output: The rendered report.
    ///   - summary: The run's one-line summary.
    ///   - options: The run's reporting options.
    /// - Throws: If the report file can't be written.
    static func deliver(_ output: String, summary: String, options: RunAndExitOptions) throws {
        guard let file = destination(options) else {
            print(output)
            return
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try output.write(to: file, atomically: true, encoding: .utf8)
        let lines = [summary] + ReportLink.lines(for: file, environment: ProcessInfo.processInfo.environment)
        print(lines.joined(separator: "\n"))
    }

    /// Picks the report file: `--output`, resolved against the current directory, or for HTML the default
    /// `.bouncer-cache/report.html` in the repository.
    ///
    /// - Parameter options: The run's reporting options.
    /// - Returns: The file, or `nil` to print to the terminal.
    static func destination(_ options: RunAndExitOptions) -> URL? {
        if let path = options.outputPath {
            let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            return URL(fileURLWithPath: path, relativeTo: current).standardizedFileURL
        }
        guard options.format == .html, let repoRoot = options.repoRoot else { return nil }
        return repoRoot.appendingPathComponent(".bouncer-cache").appendingPathComponent("report.html")
    }
}
