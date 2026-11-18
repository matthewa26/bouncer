import Foundation
import BouncerConfig
import BouncerHooks

/// Runs `preCheck`/`postCheck` hooks around an analysis run.
enum HookExecutor {
    /// A `preCheck` hook that exited non-zero, aborting the run before analysis.
    struct PreCheckFailure: Error {
        let command: String
        let exitCode: Int32
    }

    /// Runs every `preCheck` command in order, stopping and throwing at the first failure.
    ///
    /// - Parameters:
    ///   - hooks: The resolved (trust-gated) hooks to run.
    ///   - repoRoot: The directory to run each command in.
    /// - Throws: `PreCheckFailure` if any command exits non-zero.
    static func runPreCheck(_ hooks: HooksConfig?, repoRoot: URL) throws {
        guard let commands = hooks?.preCheck, !commands.isEmpty else { return }
        let results = ProcessHookRunner(workingDirectory: repoRoot).run(commands)
        guard let failure = results.first(where: { !$0.succeeded }) else { return }
        throw PreCheckFailure(command: failure.command, exitCode: failure.exitCode)
    }

    /// Runs every `postCheck` command, logging (but not throwing on) any failure.
    ///
    /// - Parameters:
    ///   - hooks: The resolved (trust-gated) hooks to run.
    ///   - repoRoot: The directory to run each command in.
    static func runPostCheck(_ hooks: HooksConfig?, repoRoot: URL) {
        guard let commands = hooks?.postCheck, !commands.isEmpty else { return }
        let results = ProcessHookRunner(workingDirectory: repoRoot).run(commands)
        guard let failure = results.first(where: { !$0.succeeded }) else { return }
        FileHandle.standardError.write(Data("bouncer: postCheck hook failed: \(failure.command)\n".utf8))
    }
}
