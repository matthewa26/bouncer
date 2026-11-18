import Foundation

/// Runs each hook command as a subprocess, with its output streamed to the caller's own.
public struct ProcessHookRunner: HookRunner {
    private let workingDirectory: URL
    private let shellExecutable: String

    /// Creates a process-backed hook runner.
    ///
    /// - Parameters:
    ///   - workingDirectory: The directory to run each command in.
    ///   - shellExecutable: The shell to invoke each command through.
    public init(workingDirectory: URL, shellExecutable: String = "/bin/sh") {
        self.workingDirectory = workingDirectory
        self.shellExecutable = shellExecutable
    }

    /// Runs each command in order, stopping at the first non-zero exit.
    ///
    /// - Parameter commands: The shell commands to run.
    /// - Returns: Every command's result, up to and including the first failure.
    public func run(_ commands: [String]) -> [HookResult] {
        var results: [HookResult] = []
        for command in commands {
            let result = runOne(command)
            results.append(result)
            if !result.succeeded { break }
        }
        return results
    }

    /// Runs a single command, inheriting the caller's stdout and stderr.
    ///
    /// - Parameter command: The shell command to run.
    /// - Returns: The command's result.
    private func runOne(_ command: String) -> HookResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellExecutable)
        process.arguments = ["-c", command]
        process.currentDirectoryURL = workingDirectory
        guard (try? process.run()) != nil else { return HookResult(command: command, exitCode: -1) }
        process.waitUntilExit()
        return HookResult(command: command, exitCode: process.terminationStatus)
    }
}
