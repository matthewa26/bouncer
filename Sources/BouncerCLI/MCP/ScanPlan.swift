import Foundation
import BouncerCore
import BouncerConfig
import BouncerGit
import BouncerProject

/// What the server was started with: the repository, the directory it scans by default, and the config flags.
struct MCPSessionDefaults: Sendable {
    /// The repository root, which paths are shown relative to.
    let repoRoot: URL
    /// The directory scanned when `scan` names no `path`.
    let rootDirectory: URL
    /// The `--profile` the server was started with.
    let profile: String?
    /// The `--config` the server was started with.
    let configPath: String?
    /// Where diagnostics go.
    let log: MCPLog
}

/// What one `scan` call asked for.
struct ScanOptions: Sendable {
    /// The directory to scan, relative to the repository root, or `nil` for the server's default.
    var path: String?
    /// A profile overriding the server's.
    var profile: String?
    /// Narrows the scan to files changed since this git revision.
    var changedSince: String?
    /// Ignores the saved last run.
    var full = false
}

/// Everything a scan needs, resolved before it starts so a bad config or revision fails the call at once.
struct ScanPlan: Sendable {
    /// The repository root.
    let repoRoot: URL
    /// The scanned directory.
    let rootDirectory: URL
    /// The merged config.
    let config: BouncerConfig
    /// The files whose findings are reported.
    let targets: TargetFileProvider
    /// The files the project rules index.
    let index: TargetFileProvider
    /// The walk over the scanned directory, honoring `exclude`: which files `verify` may analyze.
    let walker: RecursiveFileWalker
    /// The `changed_since` revision the scan was narrowed to, if any.
    let changedSince: String?
    /// The saved last run the scan starts from and saves to, if any.
    let savedRun: SavedRunSession?

    /// Whether every file under the scanned directory was analyzed, rather than only changed ones.
    var coversWholeRoot: Bool { changedSince == nil }

    /// When the session notices edited files.
    var refresh: AgentRefresh { config.agent?.refresh ?? .nextScan }

    /// Resolves a scan.
    ///
    /// - Parameters:
    ///   - options: What the call asked for.
    ///   - defaults: What the server was started with.
    /// - Throws: `ToolError` for a bad path, config, or revision.
    init(options: ScanOptions, defaults: MCPSessionDefaults) throws {
        let root = try Self.directory(options.path, defaults: defaults)
        let config = try Self.config(profile: options.profile, defaults: defaults)
        let walker = RecursiveFileWalker(rootDirectory: root, excludeGlobs: config.exclude ?? [])
        let changed = try options.changedSince.map { try Self.changedFiles(since: $0, root: root, config: config) }
        (repoRoot, rootDirectory, self.config, self.walker) = (defaults.repoRoot, root, config, walker)
        (targets, index, changedSince) = (changed ?? walker, walker, options.changedSince)
        // A narrowed scan analyzes only some files, so it neither starts from nor replaces the saved run.
        let mode: SavedRunMode = options.full ? .full : .incremental
        let saved = SavedRunSession.make(scan: mode, config: config, rootDirectory: root, repoRoot: repoRoot)
        savedRun = changed == nil ? saved : nil
    }

    /// Loads the merged config, as `review` does.
    ///
    /// - Parameters:
    ///   - profile: A profile overriding the server's.
    ///   - defaults: What the server was started with.
    /// - Returns: The merged config.
    /// - Throws: `ToolError` when a config file or the profile can't be loaded.
    static func config(profile: String?, defaults: MCPSessionDefaults) throws -> BouncerConfig {
        try ToolError.wrapping("Can't load the config") {
            try ConfigResolver.resolve(
                repoRoot: defaults.repoRoot, profile: profile ?? defaults.profile, explicitPath: defaults.configPath
            ).merged
        }
    }

    /// Resolves the directory to scan, which must be inside the repository.
    ///
    /// - Parameters:
    ///   - path: The requested path, relative to the repository root or absolute, or `nil` for the default.
    ///   - defaults: What the server was started with.
    /// - Returns: The directory.
    /// - Throws: `ToolError` when it doesn't exist or lies outside the repository.
    private static func directory(_ path: String?, defaults: MCPSessionDefaults) throws -> URL {
        guard let path else { return defaults.rootDirectory }
        let url = MCPPaths.resolve(path, repoRoot: defaults.repoRoot)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ToolError("No such path: \(path)") }
        guard MCPPaths.isInside(url, defaults.repoRoot) else { throw ToolError("\(path) is outside the repository.") }
        return url
    }

    /// Lists the files changed since a revision, as `review --changed-since` does.
    ///
    /// - Parameters:
    ///   - revision: The revision.
    ///   - root: The scanned directory.
    ///   - config: The merged config, for `exclude`.
    /// - Returns: The changed files.
    /// - Throws: `ToolError` when git can't list them.
    private static func changedFiles(
        since revision: String, root: URL, config: BouncerConfig
    ) throws -> TargetFileProvider {
        do {
            let exclude = config.exclude ?? []
            return try GitChangedFilesProvider(revision: revision, rootDirectory: root, excludeGlobs: exclude)
        } catch {
            throw ToolError("Can't list files changed since \(revision): \(error)")
        }
    }

    /// Builds the runner for the scan itself.
    ///
    /// No hooks run: a hook's output would land on standard output, which is the protocol.
    ///
    /// - Parameter onEvent: Receives the scan's events.
    /// - Returns: The runner.
    func scanRunner(onEvent: @escaping AnalysisEventHandler) -> AnalysisRunner {
        var runner = runner(files: targets)
        (runner.projectIndex, runner.savedRun, runner.onEvent) = (index, savedRun, onEvent)
        return runner
    }

    /// Builds a runner for some files with the per-file rules only, for `verify` and refreshes.
    ///
    /// - Parameter files: The files.
    /// - Returns: The runner.
    func runner(files: TargetFileProvider) -> AnalysisRunner {
        AnalysisRunner(
            repoRoot: repoRoot, fileProvider: files, mergedConfig: config, hooks: nil, coverageConfig: config.coverage,
            format: .agent, verbosity: .normal, severityThreshold: .error, useBaseline: true
        )
    }
}

/// A fixed list of files, scoped like the walk over the scanned directory, so a `.github` workflow verified on
/// its own still gets only the supply-chain rules.
struct ScopedFileList: TargetFileProvider {
    /// The files.
    let files: [URL]
    /// The walk whose rule scopes apply.
    let walker: RecursiveFileWalker

    /// Returns the files.
    ///
    /// - Returns: The files.
    func targetFiles() throws -> [URL] {
        files
    }

    /// The walk's rule scope for a file.
    ///
    /// - Parameter url: One of the files.
    /// - Returns: The rule IDs that may report in it, or `nil` for every rule.
    func ruleScope(for url: URL) -> Set<String>? {
        walker.ruleScope(for: url)
    }
}
