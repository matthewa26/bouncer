import Foundation
import BouncerReporting

/// Sends a rendered report where it belongs: printed to the terminal, or written to a file with a note of
/// where it is and how to open it.
enum ReportDelivery {
    /// Prints the report, or writes it to `--output` (or, for HTML, the default report file) and prints its
    /// location and the run's summary; then writes any further summary lines to stderr.
    ///
    /// - Parameters:
    ///   - output: The rendered report.
    ///   - summary: The run's one-line summary.
    ///   - details: More summary lines for stderr, such as the top rules and files, or none.
    ///   - options: The run's reporting options.
    /// - Throws: If the report file can't be written.
    static func deliver(_ output: String, summary: String, details: [String], options: RunAndExitOptions) throws {
        let lines = try writeToFile(output, summary: summary, options: options) ?? [output]
        print(lines.joined(separator: "\n"))
        printToStandardError(details)
    }

    /// Writes the report to its file, if it has one.
    ///
    /// - Parameters:
    ///   - output: The rendered report.
    ///   - summary: The run's one-line summary.
    ///   - options: The run's reporting options.
    /// - Returns: The summary and the file's location to print instead of the report, or `nil` without a file.
    /// - Throws: If the report file can't be written.
    private static func writeToFile(_ output: String, summary: String, options: RunAndExitOptions) throws -> [String]? {
        guard let file = destination(options) else { return nil }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try output.write(to: file, atomically: true, encoding: .utf8)
        return [summary] + ReportLink.lines(for: file, environment: ProcessInfo.processInfo.environment)
    }

    /// Writes lines to stderr, after a blank line that sets them apart from the report.
    ///
    /// - Parameter lines: The lines, or none to write nothing.
    private static func printToStandardError(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        let text = "\n" + lines.joined(separator: "\n") + "\n"
        FileHandle.standardError.write(Data(text.utf8))
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
