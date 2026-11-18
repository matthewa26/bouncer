import Foundation

/// Runs each hook command as a subprocess, with its output streamed to the caller's own.
///
/// Commands run through the platform's shell: `/bin/sh -c` on macOS and Linux, and `cmd.exe /d /s /c`
/// (from `ComSpec`) on Windows.
public struct ProcessHookRunner: HookRunner {
    private let workingDirectory: URL

    /// Creates a process-backed hook runner.
    ///
    /// - Parameter workingDirectory: The directory to run each command in.
    public init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
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
        let shell = Self.shellInvocation(for: command)
        process.executableURL = URL(fileURLWithPath: shell.executable)
        process.arguments = shell.arguments
        process.currentDirectoryURL = workingDirectory
        guard (try? process.run()) != nil else { return HookResult(command: command, exitCode: -1) }
        process.waitUntilExit()
        return HookResult(command: command, exitCode: process.terminationStatus)
    }

    /// Builds the platform shell invocation for one command.
    ///
    /// - Parameter command: The command to run.
    /// - Returns: The shell's path and the arguments that make it run `command`.
    static func shellInvocation(for command: String) -> (executable: String, arguments: [String]) {
        #if os(Windows)
        let cmd = ProcessInfo.processInfo.environment["ComSpec"] ?? #"C:\Windows\System32\cmd.exe"#
        return (cmd, ["/d", "/s", "/c", command])
        #else
        return ("/bin/sh", ["-c", command])
        #endif
    }
}
