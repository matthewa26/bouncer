import Foundation
import BouncerCore
import BouncerReporting
import BouncerConfig
import BouncerHooks
import BouncerProject

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
    /// Which findings the report shows and how: filters, paging, grouping, and summary-only output.
    var report = ReportArguments()
    /// The files the project pass indexes, or `nil` to skip project rules.
    var projectIndex: TargetFileProvider? = nil
    /// `check`'s change rules (oversized diff, complexity ratchet), or `nil` to skip them.
    var changeRules: ChangeAnalyzer? = nil
    /// Receives the run's progress events, from the hooks, the engine, and reporting.
    var onEvent: AnalysisEventHandler = { _ in }
    /// `review`'s saved last run, which this run starts from and saves to, or `nil` for neither.
    var savedRun: SavedRunSession? = nil

    /// What one run produced.
    struct Outcome {
        /// The process exit code.
        let exitCode: Int32
        /// The rendered report.
        let output: String
        /// The report's one-line summary.
        let summary: String
        /// The full analysis result, before the report's filters and paging.
        let result: AnalysisResult
        /// The findings that passed the report's filters, unpaged: what the exit code and summary count.
        let reported: AnalysisResult
    }

    /// Runs pre-check hooks, analysis, and post-check hooks, and renders the result.
    ///
    /// The report's filters apply to the exit code too, but its paging doesn't: a page that happens to hold no
    /// error still fails the run when the filtered findings do.
    ///
    /// - Returns: The exit code, the rendered report, its one-line summary, and the results behind them.
    /// - Throws: `HookExecutor.PreCheckFailure` if a `preCheck` hook fails, or an error from the engine itself.
    func run() async throws -> Outcome {
        let start = ContinuousClock.now
        try runHooks(.preCheckHooks, hooks?.preCheck) { try HookExecutor.runPreCheck(hooks, repoRoot: repoRoot) }
        let result = try analyze()
        let selected = report.selection.apply(to: result, repoRoot: repoRoot)
        let output = AnalysisPhase.report.run(emit: onEvent) { render(selected, since: start) }
        runHooks(.postCheckHooks, hooks?.postCheck) { HookExecutor.runPostCheck(hooks, repoRoot: repoRoot) }
        return outcome(result, selected: selected, output: output)
    }

    /// Bundles what a run produced, with the exit code mapped from the filtered findings.
    ///
    /// - Parameters:
    ///   - result: The full analysis result.
    ///   - selected: The findings the report's filters kept, and the page shown.
    ///   - output: The rendered report.
    /// - Returns: The run's outcome.
    private func outcome(_ result: AnalysisResult, selected: SelectedFindings, output: String) -> Outcome {
        let reported = selected.matching
        let exitCode = ExitCodeMapper.exitCode(for: reported, threshold: severityThreshold)
        let summary = ReportSummary.line(reported)
        return Outcome(exitCode: exitCode, output: output, summary: summary, result: result, reported: reported)
    }

    /// Renders the selected findings in the requested format, or only their summary under `--summary`.
    ///
    /// - Parameters:
    ///   - selected: The filtered findings and the page of them to show.
    ///   - start: When the run started, for the summary's time.
    /// - Returns: The rendered report.
    private func render(_ selected: SelectedFindings, since start: ContinuousClock.Instant) -> String {
        let elapsed = ContinuousClock.now - start
        guard report.summary else {
            let reporter = ReporterFactory.make(
                format: format, repoRoot: repoRoot, grouping: report.groupBy, selection: selected
            )
            return reporter.report(selected.page, verbosity: verbosity)
        }
        if format == .json { return JSONReporter().summary(selected.matching, repoRoot: repoRoot, elapsed: elapsed) }
        return ReportSummary.lines(selected.matching, repoRoot: repoRoot, elapsed: elapsed).joined(separator: "\n")
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

    /// Runs the engine, starting from the saved last run and saving this one when there's a saved-run session.
    ///
    /// Unlike `run()`, it runs no hooks and renders nothing, so `bouncer mcp` can call it directly.
    ///
    /// - Returns: The analysis result.
    /// - Throws: An error from the engine.
    func analyze() throws -> AnalysisResult {
        guard savedRun != nil else { return try makeEngine().run() }
        return try analyzeRecordingFiles().result
    }

    /// Runs the engine like `analyze()`, also recording each target file's stamp and per-file findings, for a
    /// session that keeps the result and later re-checks some of its files, such as `bouncer mcp`.
    ///
    /// - Returns: The result, with each target file's record.
    /// - Throws: An error from the engine.
    func analyzeRecordingFiles() throws -> RecordedRun {
        var engine = makeEngine()
        engine.priorRun = savedRun?.prior()
        let recorded = try engine.runRecordingFiles()
        savedRun?.save(recorded, repoRoot: repoRoot, emit: onEvent)
        return recorded
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
