import Foundation
import BouncerCore
import BouncerReporting
import BouncerConfig
import BouncerHooks

/// Runs one full analysis: hooks, the engine, and reporting, shared by `check` and `review`.
struct AnalysisRunner {
    let repoRoot: URL
    let fileProvider: TargetFileProvider
    let mergedConfig: BouncerConfig
    let hooks: HooksConfig?
    let coverageConfig: CoverageConfig?
    let format: OutputFormat
    let verbosity: OutputVerbosity
    let severityThreshold: Severity
    let useBaseline: Bool
    /// The files the project pass indexes, or `nil` to skip project rules.
    var projectIndex: TargetFileProvider? = nil
    /// `check`'s change rules (oversized diff, complexity ratchet), or `nil` to skip them.
    var changeRules: ChangeAnalyzer? = nil
    /// Receives the run's progress events, from the hooks, the engine, and reporting.
    var onEvent: AnalysisEventHandler = { _ in }

    /// What one run produced.
    struct Outcome {
        /// The process exit code.
        let exitCode: Int32
        /// The rendered report.
        let output: String
        /// The report's one-line summary.
        let summary: String
        /// The analysis result the report was rendered from.
        let result: AnalysisResult
    }

    /// Runs pre-check hooks, analysis, and post-check hooks, and renders the result.
    ///
    /// - Returns: The exit code, the rendered report, its one-line summary, and the result behind them.
    /// - Throws: `HookExecutor.PreCheckFailure` if a `preCheck` hook fails, or an error from the engine itself.
    func run() async throws -> Outcome {
        try runHooks(.preCheckHooks, hooks?.preCheck) { try HookExecutor.runPreCheck(hooks, repoRoot: repoRoot) }
        let result = try makeEngine().run()
        let output = AnalysisPhase.report.run(emit: onEvent) {
            ReporterFactory.make(format: format, repoRoot: repoRoot).report(result, verbosity: verbosity)
        }
        runHooks(.postCheckHooks, hooks?.postCheck) { HookExecutor.runPostCheck(hooks, repoRoot: repoRoot) }
        let exitCode = ExitCodeMapper.exitCode(for: result, threshold: severityThreshold)
        return Outcome(exitCode: exitCode, output: output, summary: ReportSummary.line(result), result: result)
    }

    /// Runs one set of hooks as a step of the run, noting each command, when there are any.
    ///
    /// - Parameters:
    ///   - phase: The hook step.
    ///   - commands: The step's commands.
    ///   - body: Runs them.
    /// - Throws: Whatever `body` throws.
    private func runHooks(_ phase: AnalysisPhase, _ commands: [String]?, _ body: () throws -> Void) rethrows {
        guard let commands, !commands.isEmpty else { return }
        try phase.run(emit: onEvent) {
            commands.forEach { onEvent(.note("hook: \($0)")) }
            try body()
        }
    }

    /// Builds the analysis engine from this runner's resolved dependencies, reporting to `onEvent`.
    ///
    /// - Returns: A fully-configured engine.
    private func makeEngine() -> AnalysisEngine {
        var engine = makeBareEngine()
        engine.onEvent = onEvent
        return engine
    }

    /// Builds the analysis engine from this runner's resolved dependencies.
    ///
    /// - Returns: A fully-configured engine with no event handler.
    private func makeBareEngine() -> AnalysisEngine {
        AnalysisEngine(
            fileProvider: fileProvider,
            contentsProvider: FileSystemContentsProvider(), knownAnalyzers: AnalyzerFactory.makeKnownAnalyzers(),
            fallbackAnalyzer: AnalyzerFactory.makeFallbackAnalyzer(),
            context: AnalysisContext(repoRoot: repoRoot, ruleSettings: mergedConfig.resolvedRuleSettings()),
            baseline: loadBaseline(),
            coverage: CoverageResolver.makeConfiguration(coverage: coverageConfig, repoRoot: repoRoot),
            project: projectIndex.map { ProjectPassFactory.make(index: $0, repoRoot: repoRoot) }, change: changeRules
        )
    }

    /// Loads the repo's accepted-findings baseline, if enabled and present.
    ///
    /// - Returns: The loaded baseline, or an empty one.
    private func loadBaseline() -> Baseline {
        guard useBaseline else { return .empty }
        return (try? JSONBaselineStore().load(from: BouncerPaths.baseline(repoRoot: repoRoot))) ?? .empty
    }
}
