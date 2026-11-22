import ArgumentParser
import Foundation
import BouncerCore
import BouncerConfig
import BouncerGit

/// Recursively audits a directory, independent of git state.
///
/// The ad-hoc code-review entry point: useful for auditing an unfamiliar
/// codebase, or for a coding agent doing a full-repo review rather than a
/// post-edit self-check.
struct Review: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "review", abstract: "Recursively analyze a directory.")

    @Argument(help: "The directory to analyze.")
    var path: String = "."

    @Option(help: "An explicit .bouncer path, overriding the layered config resolution.")
    var config: String?

    @Option(help: ArgumentHelp(stringLiteral: OutputFormat.help))
    var format: OutputFormat = .console

    @Option(help: "Write the report to this file instead of printing it.")
    var output: String?

    @Option(help: "verbose, normal, quiet, or condensed.")
    var verbosity: OutputVerbosity?

    @Option(help: "The minimum severity that causes a non-zero exit.")
    var severityThreshold: Severity = .error

    @Option(help: "Apply a bundled preset, such as kirby, as the base config layer.")
    var profile: String?

    @Option(help: "A coverage report path, overriding .bouncer's configured one.")
    var coverageReport: String?

    @Option(help: "xccov, lcov, or auto.")
    var coverageFormat: String?

    @Option(parsing: .upToNextOption, help: "Glob patterns, relative to the analyzed directory, to exclude.")
    var exclude: [String] = []

    @Option(help: "Analyze only files changed since this git revision, plus untracked files.")
    var changedSince: String?

    @Flag(help: "Run this repo's hooks without an interactive trust prompt.")
    var allowHooks = false

    @Flag(help: "Skip the pre-flight update check for this run.")
    var noUpdateCheck = false

    @OptionGroup var progressArguments: ProgressArguments
    @OptionGroup var reportArguments: ReportArguments

    /// Resolves config, gates hooks, runs the analysis, and exits with the mapped code.
    ///
    /// - Throws: `ExitCode` on completion, or an error if the engine itself fails.
    func run() async throws {
        let rootDirectory = URL(fileURLWithPath: path)
        let repoRoot = GitRepoLocator.repoRoot(startingAt: rootDirectory) ?? rootDirectory
        let resolution = try ConfigResolver.resolve(repoRoot: repoRoot, profile: profile, explicitPath: config)
        let hooks = HooksGate.resolve(
            repoConfig: resolution.rawRepo, globalHooks: resolution.rawGlobal.hooks,
            mergedHooks: resolution.merged.hooks, repoRoot: repoRoot, allowHooksFlag: allowHooks
        )
        let files = try selectFiles(rootDirectory, config: resolution.merged)
        try await runAnalysis(files: files, repoRoot: repoRoot, resolution: resolution, hooks: hooks)
    }

    /// Chooses the files to analyze and index, from the reviewed directory, `--exclude`, and `--changed-since`.
    ///
    /// - Parameters:
    ///   - rootDirectory: The directory being analyzed.
    ///   - config: The merged config, for its `exclude` globs.
    /// - Returns: The file selection.
    /// - Throws: `ExitCode(2)` if `--changed-since` can't list the changed files.
    private func selectFiles(_ rootDirectory: URL, config: BouncerConfig) throws -> ReviewFileSelection {
        let excludeGlobs = exclude + (config.exclude ?? [])
        return try ReviewFileSelection.resolve(rootDirectory: rootDirectory, excludeGlobs: excludeGlobs, changedSince: changedSince)
    }

    /// Runs the analysis and update check, then exits with the mapped code.
    ///
    /// - Parameters:
    ///   - files: The files to analyze and to index for project rules.
    ///   - repoRoot: The context root used for baseline and rule reporting.
    ///   - resolution: The resolved config layers.
    ///   - hooks: The trust-gated hooks to run.
    /// - Throws: `ExitCode` on completion.
    private func runAnalysis(
        files: ReviewFileSelection, repoRoot: URL, resolution: ConfigResolution, hooks: HooksConfig?
    ) async throws {
        let runner = makeRunner(files: files, repoRoot: repoRoot, resolution: resolution, hooks: hooks)
        var options = RunAndExitOptions(
            updateCheckConfig: resolution.merged.updateCheck, noUpdateCheckFlag: noUpdateCheck,
            isAgentInvocation: format == .json, format: format, outputPath: output, repoRoot: repoRoot
        )
        options.progress = progressArguments
        options.context = RunLog.configLines(repoRoot: repoRoot, profile: profile, explicitPath: config)
            + [files.logLine]
        try await RunAndExit.run(runner, options: options)
    }

    /// Builds the analysis runner for this invocation.
    ///
    /// - Parameters:
    ///   - files: The files to analyze and to index for project rules.
    ///   - repoRoot: The context root used for baseline and rule reporting.
    ///   - resolution: The resolved config layers.
    ///   - hooks: The trust-gated hooks to run.
    /// - Returns: A configured analysis runner.
    private func makeRunner(
        files: ReviewFileSelection, repoRoot: URL, resolution: ConfigResolution, hooks: HooksConfig?
    ) -> AnalysisRunner {
        AnalysisRunner(
            repoRoot: repoRoot, fileProvider: files.targets, mergedConfig: resolution.merged, hooks: hooks,
            coverageConfig: resolvedCoverageConfig(resolution.merged.coverage), format: format,
            verbosity: verbosity ?? resolution.merged.output?.verbosity ?? .normal,
            severityThreshold: severityThreshold, useBaseline: true, report: reportArguments,
            projectIndex: files.index
        )
    }

    /// Overlays `--coverage-report`/`--coverage-format` on top of the merged coverage config.
    ///
    /// - Parameter merged: The merged `.bouncer` coverage section.
    /// - Returns: The coverage config to run with.
    private func resolvedCoverageConfig(_ merged: CoverageConfig?) -> CoverageConfig? {
        guard coverageReport != nil || coverageFormat != nil else { return merged }
        var result = merged ?? CoverageConfig()
        result.enabled = true
        result.reportPath = coverageReport ?? result.reportPath
        result.format = coverageFormat ?? result.format
        return result
    }
}
