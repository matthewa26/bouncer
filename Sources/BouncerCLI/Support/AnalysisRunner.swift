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

    /// Runs pre-check hooks, analysis, and post-check hooks, and renders the result.
    ///
    /// - Returns: The process exit code, the rendered report, and its one-line summary.
    /// - Throws: `HookExecutor.PreCheckFailure` if a `preCheck` hook fails, or an error from the engine itself.
    func run() async throws -> (exitCode: Int32, output: String, summary: String) {
        try HookExecutor.runPreCheck(hooks, repoRoot: repoRoot)
        let engine = makeEngine()
        let result = try engine.run()
        let output = ReporterFactory.make(format: format, repoRoot: repoRoot).report(result, verbosity: verbosity)
        HookExecutor.runPostCheck(hooks, repoRoot: repoRoot)
        return (ExitCodeMapper.exitCode(for: result, threshold: severityThreshold), output, ReportSummary.line(result))
    }

    /// Builds the analysis engine from this runner's resolved dependencies.
    ///
    /// - Returns: A fully-configured engine.
    private func makeEngine() -> AnalysisEngine {
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
