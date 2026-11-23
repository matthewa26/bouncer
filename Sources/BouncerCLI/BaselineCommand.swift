import ArgumentParser
import Foundation
import BouncerCore
import BouncerConfig
import BouncerGit
import BouncerReporting

/// Manages `.bouncer-baseline.json`, the snapshot of accepted pre-existing findings.
struct BaselineCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "baseline", abstract: "Manage the accepted-findings baseline.",
        subcommands: [Update.self, Clear.self], defaultSubcommand: Update.self
    )

    /// Runs a full analysis and accepts every current finding into the baseline.
    struct Update: AsyncParsableCommand {
        @Argument(help: "The directory to analyze.")
        var path: String = "."

        @OptionGroup var progressArguments: ProgressArguments

        /// Analyzes the directory and writes every finding's fingerprint to the baseline.
        ///
        /// - Throws: If analysis or writing the baseline fails.
        func run() async throws {
            let rootDirectory = URL(fileURLWithPath: path)
            let repoRoot = GitRepoLocator.repoRoot(startingAt: rootDirectory) ?? rootDirectory
            let result = try runFullAnalysis(rootDirectory: rootDirectory, repoRoot: repoRoot)
            let baseline = BaselineBuilder.build(from: result, repoRoot: repoRoot)
            try JSONBaselineStore().write(baseline, to: BouncerPaths.baseline(repoRoot: repoRoot))
            let baselinePath = BouncerPaths.baseline(repoRoot: repoRoot).path
            print("Wrote \(baseline.fingerprints.count) fingerprint(s) to \(baselinePath).")
        }

        /// Runs analysis with no existing baseline applied, so every finding is captured, showing its progress
        /// on stderr, with `--jobs` (else the config's `jobs`) files at once.
        ///
        /// - Parameters:
        ///   - rootDirectory: The directory to analyze.
        ///   - repoRoot: The repository root, used for rule context and relative paths.
        /// - Returns: The unfiltered analysis result.
        /// - Throws: If analysis fails.
        private func runFullAnalysis(rootDirectory: URL, repoRoot: URL) throws -> AnalysisResult {
            let resolution = try ConfigResolver.resolve(repoRoot: repoRoot, profile: nil, explicitPath: nil)
            var engine = FullAnalysisEngineFactory.make(
                rootDirectory: rootDirectory, repoRoot: repoRoot, resolution: resolution
            )
            engine.jobs = resolution.merged.jobs(overriddenBy: progressArguments.jobs)
            return try run(engine, repoRoot: repoRoot)
        }

        /// Runs an engine with its progress shown on stderr, cleared however the run ends.
        ///
        /// - Parameters:
        ///   - engine: The engine.
        ///   - repoRoot: The repository root, which progress paths are shown relative to.
        /// - Returns: The analysis result.
        /// - Throws: If analysis fails.
        private func run(_ engine: AnalysisEngine, repoRoot: URL) throws -> AnalysisResult {
            let context = RunLog.configLines(repoRoot: repoRoot, profile: nil, explicitPath: nil)
                + [RunLog.jobsLine(engine.jobs)]
            let invocation = ProgressInvocation()
            let log = RunLog.start(progressArguments, invocation: invocation, root: repoRoot, context: context)
            var engine = engine
            engine.onEvent = log.onEvent
            defer { log.finish() }
            return try engine.run()
        }
    }

    /// Deletes the baseline file, if one exists.
    struct Clear: AsyncParsableCommand {
        @Argument(help: "The repository whose baseline to clear.")
        var path: String = "."

        /// Removes `.bouncer-baseline.json` from the repository root.
        ///
        /// - Throws: If the file exists but can't be removed.
        func run() async throws {
            let repoRoot = GitRepoLocator.repoRoot(startingAt: URL(fileURLWithPath: path)) ?? URL(fileURLWithPath: path)
            let baselinePath = BouncerPaths.baseline(repoRoot: repoRoot)
            guard FileManager.default.fileExists(atPath: baselinePath.path) else {
                print("No baseline to clear.")
                return
            }
            try FileManager.default.removeItem(at: baselinePath)
            print("Cleared \(baselinePath.path).")
        }
    }
}
