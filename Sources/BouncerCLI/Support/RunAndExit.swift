import ArgumentParser
import Foundation
import BouncerConfig
import BouncerUpdateCheck

/// Everything `RunAndExit` needs beyond the runner itself, bundled to keep call sites short.
struct RunAndExitOptions {
    let updateCheckConfig: UpdateCheckConfig?
    let noUpdateCheckFlag: Bool
    let isAgentInvocation: Bool
    let format: OutputFormat
}

/// Runs an `AnalysisRunner`, prints its output, checks for an update, and exits with its code.
///
/// Shared by `check` and `review`, since both do exactly this once their own
/// setup (file provider, config, hooks) differs.
enum RunAndExit {
    /// Runs the analysis, prints the report, checks for an update, and throws the mapped `ExitCode`.
    ///
    /// - Parameters:
    ///   - runner: The configured analysis runner.
    ///   - options: The update-check and reporting options this run should use.
    /// - Throws: `ExitCode` on completion, or `ExitCode(2)` if a preCheck hook failed.
    static func run(_ runner: AnalysisRunner, options: RunAndExitOptions) async throws {
        do {
            try await attemptRun(runner, options: options)
        } catch let failure as HookExecutor.PreCheckFailure {
            FileHandle.standardError.write(Data("bouncer: preCheck hook failed: \(failure.command)\n".utf8))
            throw ExitCode(2)
        }
    }

    /// Runs the analysis, prints its output, checks for an update, and throws the mapped exit code.
    ///
    /// - Parameters:
    ///   - runner: The configured analysis runner.
    ///   - options: The update-check and reporting options this run should use.
    /// - Throws: `ExitCode` with the analysis result's mapped code, or a `HookExecutor.PreCheckFailure`.
    private static func attemptRun(_ runner: AnalysisRunner, options: RunAndExitOptions) async throws {
        let (exitCode, output) = try await runner.run()
        print(output)
        await UpdateCheckPresenter.run(
            config: options.updateCheckConfig, noUpdateCheckFlag: options.noUpdateCheckFlag,
            isAgentInvocation: options.isAgentInvocation, format: options.format
        )
        throw ExitCode(exitCode)
    }
}
