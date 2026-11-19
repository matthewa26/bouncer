import Foundation
import BouncerCore
import BouncerConfig
import BouncerProject

/// Builds the engine's project pass: the files to index, the repo's facts cache, and the project rules.
enum ProjectPassFactory {
    /// Builds a project pass over a set of files, with git history for the churn-based rules.
    ///
    /// - Parameters:
    ///   - index: The files to index.
    ///   - repoRoot: The repository root, where `.bouncer-cache/` lives.
    /// - Returns: The project pass.
    static func make(index: TargetFileProvider, repoRoot: URL) -> ProjectPhase {
        let rules = ProjectRules(history: GitLogHistorySource(), measurer: makeMeasurer())
        return ProjectPhase(indexProvider: index, store: JSONFactsStore(repoRoot: repoRoot), analyzer: rules)
    }

    /// The files `check` indexes: the whole repo when `project.inCheck` is on, otherwise none.
    ///
    /// - Parameters:
    ///   - repoRoot: The repository root.
    ///   - config: The merged config.
    /// - Returns: A walker over the repo honoring `exclude`, or `nil` when project rules are off in `check`.
    static func checkIndex(repoRoot: URL, config: BouncerConfig) -> TargetFileProvider? {
        guard config.project?.inCheck == true else { return nil }
        return RecursiveFileWalker(rootDirectory: repoRoot, excludeGlobs: config.exclude ?? [])
    }

    /// Builds `check`'s change rules, which run whether or not `project.inCheck` is on.
    ///
    /// - Parameters:
    ///   - checksStagedDiff: Whether `check` is checking the staged files, so the diff's size applies.
    ///   - config: The merged config, for its `exclude` globs.
    /// - Returns: The change rules.
    static func changeRules(checksStagedDiff: Bool, config: BouncerConfig) -> ChangeAnalyzer {
        ChangeRules(
            source: GitChangeSource(), measurer: makeMeasurer(), checksStagedDiff: checksStagedDiff,
            exclude: config.exclude ?? []
        )
    }

    /// Builds the function measurer the git-aware rules weigh complexity with.
    ///
    /// - Returns: A measurer over every dedicated language analyzer.
    private static func makeMeasurer() -> FunctionMeasuring {
        AnalyzerFunctionMeasurer(analyzers: AnalyzerFactory.makeKnownAnalyzers())
    }
}
