import Foundation
import BouncerCore
import BouncerConfig
import BouncerGit
import BouncerMCP
import BouncerReporting

extension MCPSession {
    /// Answers `findings`: one page of the matching findings, in `--format agent` lines.
    ///
    /// - Parameter arguments: `rule`, `path`, `severity`, `group_by`, `cursor`, and the budget.
    /// - Returns: The page.
    /// - Throws: `ToolError` for bad arguments or when there's no result.
    func findings(_ arguments: ToolArguments) async throws -> MCPAnswer {
        let selection = try arguments.selection()
        let grouping = try arguments.choice("group_by", among: ReportGrouping.allCases) ?? .file
        let offset = try arguments.cursorOffset()
        let reading = try await reading()
        let request = page(of: reading.snapshot, selection: selection, grouping: grouping, offset: offset)
        return MCPAnswer(ToolText.findings(header: reading.header, page: request, budget: arguments.budget))
    }

    /// Picks the matching findings of a result for a page.
    ///
    /// - Parameters:
    ///   - snapshot: The result.
    ///   - selection: The filters.
    ///   - grouping: How the page groups findings.
    ///   - offset: Where it starts.
    /// - Returns: The page request.
    private func page(
        of snapshot: ResultSnapshot, selection: FindingSelection, grouping: ReportGrouping, offset: Int
    ) -> FindingsRequest {
        let all = ordered(snapshot, grouping: grouping)
        let matching = selection.isActive ? selection.filtering(all, repoRoot: defaults.repoRoot) : all
        return FindingsRequest(
            repoRoot: defaults.repoRoot, findings: matching, offset: offset, grouping: grouping,
            unfilteredTotal: selection.isActive ? all.count : nil
        )
    }

    /// Answers `verify`: re-analyzes the named files and returns only how their findings changed.
    ///
    /// - Parameter arguments: `files` and the budget.
    /// - Returns: The delta.
    /// - Throws: `ToolError` for bad arguments, when there's no result, or when the files can't be analyzed.
    func verify(_ arguments: ToolArguments) async throws -> MCPAnswer {
        let paths = try arguments.strings("files")
        guard !paths.isEmpty else {
            throw ToolError("files is required: the paths you edited, relative to the repo root.")
        }
        let reading = try await reading()
        let reanalysis = try await reanalyze(paths.map { MCPPaths.resolve($0, repoRoot: defaults.repoRoot) })
        noteVerified(reanalysis.targets.analyzedPaths)
        let (budget, root) = (arguments.budget, defaults.repoRoot)
        return MCPAnswer(ToolText.verify(header: reading.header, reanalysis, repoRoot: root, budget: budget))
    }

    /// Answers `check`: the staged-diff check the pre-commit hook runs, with only what would block the commit.
    ///
    /// - Parameter arguments: The budget.
    /// - Returns: The blocking findings, or that nothing blocks the commit.
    /// - Throws: `ToolError` when the config can't be loaded or the check fails.
    func check(_ arguments: ToolArguments) async throws -> MCPAnswer {
        let config = try ScanPlan.config(profile: nil, defaults: defaults)
        let repoRoot = defaults.repoRoot
        let outcome = await BlockingWork.run { try StagedCheck.runner(repoRoot: repoRoot, config: config).analyze() }
        let result = try ToolError.wrapping("The check failed") { try outcome.get() }
        return MCPAnswer(ToolText.check(result, repoRoot: repoRoot, budget: arguments.budget))
    }
}

/// Builds the runner `check` uses with no `--files`: the staged diff, change rules included, baseline honored.
enum StagedCheck {
    /// Builds the runner. No hooks run: their output would land on standard output, which is the protocol.
    ///
    /// - Parameters:
    ///   - repoRoot: The repository root.
    ///   - config: The merged config.
    /// - Returns: The runner.
    static func runner(repoRoot: URL, config: BouncerConfig) -> AnalysisRunner {
        let filter = ExcludeFilter(root: repoRoot, globs: config.exclude ?? [])
        let files = ExcludingFileProvider(base: GitStagedFilesProvider(repoRoot: repoRoot), filter: filter)
        return AnalysisRunner(
            repoRoot: repoRoot, fileProvider: files, mergedConfig: config, hooks: nil, coverageConfig: nil,
            format: .agent, verbosity: .normal, severityThreshold: .error, useBaseline: true,
            projectIndex: ProjectPassFactory.checkIndex(repoRoot: repoRoot, config: config),
            changeRules: ProjectPassFactory.changeRules(checksStagedDiff: true, config: config)
        )
    }
}

/// Answers `explain_rule` from the rule catalog.
enum RuleExplainer {
    /// Explains a rule, or suggests close IDs for an unknown one.
    ///
    /// - Parameter arguments: `id`.
    /// - Returns: The explanation.
    /// - Throws: `ToolError` when the ID is missing or unknown.
    static func explain(_ arguments: ToolArguments) throws -> MCPAnswer {
        guard let id = try arguments.string("id"), !id.isEmpty else { throw ToolError("id is required.") }
        if let explanation = RuleCatalog.explain(id) { return MCPAnswer(explanation.text) }
        throw ToolError(unknown(id))
    }

    /// Says a rule ID is unknown, suggesting close ones.
    ///
    /// - Parameter id: The unknown ID.
    /// - Returns: The message.
    private static func unknown(_ id: String) -> String {
        let close = NameSuggestions.closest(to: id, among: RuleCatalog.ruleIDs)
        guard !close.isEmpty else { return "Unknown rule \(id). Rule IDs look like force-unwrap or long-function." }
        return "Unknown rule \(id). Did you mean: \(close.joined(separator: ", "))?"
    }
}
