import ArgumentParser
import Foundation
import BouncerConfig
import BouncerReporting
import BouncerUpdateCheck

/// Everything `RunAndExit` needs beyond the runner itself, bundled to keep call sites short.
struct RunAndExitOptions {
    let updateCheckConfig: UpdateCheckConfig?
    let noUpdateCheckFlag: Bool
    let isAgentInvocation: Bool
    let format: OutputFormat
    /// Where `--output` asked for the report to go, or `nil` for the terminal.
    var outputPath: String? = nil
    /// The repository root, which holds the default HTML report location.
    var repoRoot: URL? = nil
    /// The `--progress`, `--verbose`, and `--jobs` options.
    var progress = ProgressArguments()
    /// What the command already knows about the run, such as where its config came from, for the verbose log.
    var context: [String] = []
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
        var runner = runner
        runner.jobs = options.progress.jobs ?? runner.jobs
        let log = startLog(options, jobs: runner.resolvedJobs)
        do {
            try await attemptRun(runner, options: options, log: log)
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
    ///   - log: The run's progress display.
    /// - Throws: `ExitCode` with the analysis result's mapped code, or a `HookExecutor.PreCheckFailure`.
    private static func attemptRun(_ runner: AnalysisRunner, options: RunAndExitOptions, log: RunLog) async throws {
        let start = ContinuousClock.now
        let outcome = try await analyze(runner, log: log)
        let details = summaryDetails(outcome, runner: runner, options: options, elapsed: ContinuousClock.now - start)
        try ReportDelivery.deliver(outcome.output, summary: outcome.summary, details: details, options: options)
        await UpdateCheckPresenter.run(
            config: options.updateCheckConfig, noUpdateCheckFlag: options.noUpdateCheckFlag,
            isAgentInvocation: options.isAgentInvocation, format: options.format
        )
        throw ExitCode(outcome.exitCode)
    }

    /// Starts the progress display the run's options ask for. Xcode and agent output count as an agent
    /// invocation, so `--progress auto` stays out of the build log and the agent's context.
    ///
    /// - Parameters:
    ///   - options: The run's options.
    ///   - jobs: How many files the run analyzes at once, logged when verbose.
    /// - Returns: The running log.
    private static func startLog(_ options: RunAndExitOptions, jobs: Int) -> RunLog {
        var invocation = ProgressInvocation()
        invocation.isAgentInvocation = options.isAgentInvocation || [.xcode, .agent].contains(options.format)
        let context = options.context + [RunLog.jobsLine(jobs)]
        return RunLog.start(options.progress, invocation: invocation, root: options.repoRoot, context: context)
    }

    /// Runs the analysis with its events going to the progress display, which is cleared however it ends.
    ///
    /// - Parameters:
    ///   - runner: The configured analysis runner.
    ///   - log: The run's progress display.
    /// - Returns: What the run produced.
    /// - Throws: Whatever the runner throws.
    private static func analyze(_ runner: AnalysisRunner, log: RunLog) async throws -> AnalysisRunner.Outcome {
        var runner = runner
        runner.onEvent = log.onEvent
        defer { log.finish() }
        return try await runner.run()
    }

    /// Builds the multi-line summary printed to stderr after the report, for a person watching the run.
    ///
    /// It's left out for agent invocations, at `quiet` or `condensed` verbosity, and under `--summary`, which
    /// printed it already; and for a report printed to the terminal unless stderr is a terminal too. A report
    /// written to a file already has its one-line summary on stdout, so only the rest follows.
    ///
    /// - Parameters:
    ///   - outcome: What the run produced.
    ///   - runner: The runner, for its verbosity and repository root.
    ///   - options: The run's reporting options.
    ///   - elapsed: How long the run took.
    /// - Returns: The lines to print, possibly none.
    private static func summaryDetails(
        _ outcome: AnalysisRunner.Outcome, runner: AnalysisRunner, options: RunAndExitOptions, elapsed: Duration
    ) -> [String] {
        guard !options.isAgentInvocation, !runner.report.summary, [.normal, .verbose].contains(runner.verbosity) else {
            return []
        }
        let toFile = ReportDelivery.destination(options) != nil
        let forPerson = Terminal.standardErrorIsInteractive && ![.json, .agent].contains(options.format)
        guard toFile || forPerson else { return [] }
        let lines = ReportSummary.lines(outcome.reported, repoRoot: runner.repoRoot, elapsed: elapsed)
        return toFile ? Array(lines.dropFirst()) : lines
    }
}
