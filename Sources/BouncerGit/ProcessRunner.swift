import Foundation
import BouncerCore

/// Runs a subprocess and captures its output, shared by every git-invoking type.
enum ProcessRunner {
    /// Runs a command and returns its trimmed standard output.
    ///
    /// - Parameters:
    ///   - executable: The tool's name, looked up on `PATH`, such as `git`.
    ///   - arguments: The command-line arguments to pass.
    ///   - currentDirectory: The working directory to run in.
    /// - Returns: The command's standard output, or `nil` if it isn't on `PATH` or exited non-zero.
    static func run(_ executable: String, _ arguments: [String], currentDirectory: URL) -> String? {
        output(executable, arguments, currentDirectory: currentDirectory)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs a command and returns its standard output exactly as written, such as a file's contents.
    ///
    /// - Parameters:
    ///   - executable: The tool's name, looked up on `PATH`, such as `git`.
    ///   - arguments: The command-line arguments to pass.
    ///   - currentDirectory: The working directory to run in.
    /// - Returns: The untrimmed output, or `nil` if the tool isn't on `PATH`, exited non-zero, or wrote
    ///   something other than UTF-8.
    static func output(_ executable: String, _ arguments: [String], currentDirectory: URL) -> String? {
        guard let path = ExecutableLocator.path(of: executable) else { return nil }
        let pipe = Pipe()
        let process = makeProcess(path, arguments, currentDirectory: currentDirectory, output: pipe)
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Builds a configured, unstarted process.
    ///
    /// - Parameters:
    ///   - executable: The absolute path to the executable.
    ///   - arguments: The command-line arguments to pass.
    ///   - currentDirectory: The working directory to run in.
    ///   - output: The pipe to capture standard output into.
    /// - Returns: The configured process.
    private static func makeProcess(
        _ executable: String, _ arguments: [String], currentDirectory: URL, output: Pipe
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = output
        process.standardError = Pipe()
        return process
    }
}
