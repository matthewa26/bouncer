import ArgumentParser
import Foundation
import BouncerCore
import BouncerConfig
import BouncerGit

/// Analyzes staged, explicitly listed, or piped-in files and exits non-zero on violations.
///
/// This is what `.husky/pre-commit` calls, and also the agent post-edit
/// self-check entry point via `--files`/`--stdin`.
struct Check: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check", abstract: "Analyze files and exit non-zero on violations."
    )

    @Option(parsing: .upToNextOption, help: "Analyze exactly these files instead of the staged git diff.")
    var files: [String] = []

    @Flag(help: "Read a newline-delimited file list from stdin instead of the staged git diff.")
    var stdin = false

    @Option(help: "The minimum severity that causes a non-zero exit.")
    var severityThreshold: Severity = .error

    @Option(help: "An explicit .bouncer path, overriding the layered config resolution.")
    var config: String?

    @Option(help: "console or json.")
    var format: OutputFormat = .console

    @Option(help: "verbose, normal, quiet, or condensed.")
    var verbosity: OutputVerbosity?

    @Flag(help: "Check test coverage against the configured threshold.")
    var coverage = false

    @Flag(help: "Ignore the baseline file and report every finding.")
    var noBaseline = false

    @Flag(help: "Skip the pre-flight update check for this run.")
    var noUpdateCheck = false

    @Flag(help: "Run this repo's hooks without an interactive trust prompt.")
    var allowHooks = false

    @Option(help: "Apply a bundled preset, such as kirby, as the base config layer.")
    var profile: String?

    /// Resolves config, gates hooks, runs the analysis, and exits with the mapped code.
    ///
    /// - Throws: `ExitCode` on completion, or an error if the engine itself fails.
    func run() async throws {
        let repoRoot = GitRepoLocator.repoRoot(startingAt: currentDirectory()) ?? currentDirectory()
        let resolution = try ConfigResolver.resolve(repoRoot: repoRoot, profile: profile, explicitPath: config)
        let hooks = HooksGate.resolve(
            repoConfig: resolution.rawRepo, globalHooks: resolution.rawGlobal.hooks,
            mergedHooks: resolution.merged.hooks, repoRoot: repoRoot, allowHooksFlag: allowHooks
        )
        try await runAnalysis(repoRoot: repoRoot, resolution: resolution, hooks: hooks)
    }

    /// Runs the analysis and update check, then exits with the mapped code.
    ///
    /// - Parameters:
    ///   - repoRoot: The repository root.
    ///   - resolution: The resolved config layers.
    ///   - hooks: The trust-gated hooks to run.
    /// - Throws: `ExitCode` on completion.
    private func runAnalysis(repoRoot: URL, resolution: ConfigResolution, hooks: HooksConfig?) async throws {
        let runner = try makeRunner(repoRoot: repoRoot, resolution: resolution, hooks: hooks)
        let options = RunAndExitOptions(
            updateCheckConfig: resolution.merged.updateCheck, noUpdateCheckFlag: noUpdateCheck,
            isAgentInvocation: isAgentInvocation, format: format
        )
        try await RunAndExit.run(runner, options: options)
    }

    /// Builds the analysis runner for this invocation.
    ///
    /// - Parameters:
    ///   - repoRoot: The repository root.
    ///   - resolution: The resolved config layers.
    ///   - hooks: The trust-gated hooks to run.
    /// - Returns: A configured analysis runner.
    /// - Throws: If the file provider can't be built (an unreadable `--stdin` list, for example).
    private func makeRunner(repoRoot: URL, resolution: ConfigResolution, hooks: HooksConfig?) throws -> AnalysisRunner {
        AnalysisRunner(
            repoRoot: repoRoot, fileProvider: try makeFileProvider(repoRoot: repoRoot, resolution: resolution),
            mergedConfig: resolution.merged,
            hooks: hooks, coverageConfig: coverage ? resolution.merged.coverage : nil, format: format,
            verbosity: verbosity ?? resolution.merged.output?.verbosity ?? .normal,
            severityThreshold: severityThreshold, useBaseline: !noBaseline,
            projectIndex: ProjectPassFactory.checkIndex(repoRoot: repoRoot, config: resolution.merged),
            changeRules: ProjectPassFactory.changeRules(checksStagedDiff: !isAgentInvocation, config: resolution.merged)
        )
    }

    /// Builds the file provider matching how this invocation was made, honoring `exclude`.
    ///
    /// - Parameters:
    ///   - repoRoot: The repository root: the staged provider's base and what `exclude` globs are relative to.
    ///   - resolution: The resolved config layers, for their `exclude` globs.
    /// - Returns: The `--files`/`--stdin` list or the staged files, minus any excluded ones.
    private func makeFileProvider(repoRoot: URL, resolution: ConfigResolution) throws -> TargetFileProvider {
        let filter = ExcludeFilter(root: repoRoot, globs: resolution.merged.exclude ?? [])
        return ExcludingFileProvider(base: makeBaseFileProvider(repoRoot: repoRoot), filter: filter)
    }

    /// Builds the unfiltered file provider matching how this invocation was made.
    ///
    /// - Parameter repoRoot: The repository root, used as the git-staged provider's base.
    /// - Returns: An explicit-list provider for `--files`/`--stdin`, or the staged-files provider.
    private func makeBaseFileProvider(repoRoot: URL) -> TargetFileProvider {
        if !files.isEmpty { return ExplicitFileListProvider(files: files.map { URL(fileURLWithPath: $0) }) }
        if stdin { return ExplicitFileListProvider(files: readStdinFileList()) }
        return GitStagedFilesProvider(repoRoot: repoRoot)
    }

    /// Reads a newline-delimited file list from standard input.
    ///
    /// - Returns: The listed files' locations.
    private func readStdinFileList() -> [URL] {
        var files: [URL] = []
        while let line = readLine(), !line.isEmpty { files.append(URL(fileURLWithPath: line)) }
        return files
    }

    /// Whether this invocation used an agent-facing flag rather than a plain interactive run.
    private var isAgentInvocation: Bool { !files.isEmpty || stdin }

    /// The process's current working directory.
    ///
    /// - Returns: The current directory's location.
    private func currentDirectory() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
