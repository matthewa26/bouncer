/// The outcome of running one hook command.
public struct HookResult: Sendable, Equatable {
    /// The command that was run.
    public let command: String
    /// The process's exit code.
    public let exitCode: Int32

    /// Creates a hook result.
    ///
    /// - Parameters:
    ///   - command: The command that was run.
    ///   - exitCode: The process's exit code.
    public init(command: String, exitCode: Int32) {
        self.command = command
        self.exitCode = exitCode
    }

    /// Whether the command exited successfully.
    public var succeeded: Bool { exitCode == 0 }
}

/// Runs `.bouncer`'s `hooks.preCheck`/`hooks.postCheck` shell commands.
public protocol HookRunner: Sendable {
    /// Runs a list of shell commands in order, stopping at the first failure.
    ///
    /// - Parameter commands: The shell commands to run, in order.
    /// - Returns: Every command's result, up to and including the first failure.
    func run(_ commands: [String]) -> [HookResult]
}
