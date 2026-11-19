import Foundation

/// Runs rules over the whole project's module facts, such as import cycles and unused exports.
public protocol ProjectAnalyzer: Sendable {
    /// Finds project-level problems.
    ///
    /// - Parameters:
    ///   - facts: Every indexed file's facts.
    ///   - targets: The repo-relative paths being checked; a problem spanning several files, such as a
    ///     cycle, should be reported in one of these when it involves any.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The findings, each attributed to one file and line.
    func findings(for facts: [FileFacts], targets: Set<String>, context: AnalysisContext) -> [Finding]
}

/// Remembers files' module facts between runs, keyed by path and content hash.
public protocol FactsStore: Sendable {
    /// Looks up cached facts.
    ///
    /// - Parameters:
    ///   - path: The repo-relative path.
    ///   - contentHash: The file's current content hash.
    /// - Returns: The cached facts if the file hasn't changed since they were stored.
    func cachedFacts(path: String, contentHash: String) -> FileFacts?

    /// Replaces the stored facts with a new set.
    ///
    /// - Parameter facts: Every indexed file's facts.
    /// - Throws: If the store can't be written.
    func save(_ facts: [FileFacts]) throws
}

/// The engine's optional second pass: index every project file's facts, then run project rules.
public struct ProjectPhase: Sendable {
    private let indexProvider: TargetFileProvider
    private let store: FactsStore
    private let analyzer: ProjectAnalyzer

    /// Creates a project phase.
    ///
    /// - Parameters:
    ///   - indexProvider: The files to index; for `check`, the whole repo rather than just staged files.
    ///   - store: The facts cache.
    ///   - analyzer: The project rules.
    public init(indexProvider: TargetFileProvider, store: FactsStore, analyzer: ProjectAnalyzer) {
        self.indexProvider = indexProvider
        self.store = store
        self.analyzer = analyzer
    }

    /// Reads a file, and parses a file into module facts, for the project phase.
    struct FileAccess {
        let read: (URL) throws -> SourceFile
        let parse: (SourceFile) throws -> ModuleFacts?
    }

    /// Indexes the project and returns project findings that land in one of the target files.
    ///
    /// - Parameters:
    ///   - targets: The repo-relative paths of the files being checked.
    ///   - context: Repo-wide state.
    ///   - access: Reads files and parses their module facts.
    /// - Returns: Project findings in target files.
    /// - Throws: If the index can't be listed or the cache can't be saved.
    func findings(targets: Set<String>, context: AnalysisContext, access: FileAccess) throws -> [Finding] {
        let facts = try indexProvider.targetFiles().compactMap { try facts(for: $0, context: context, access: access) }
        try store.save(facts)
        return analyzer.findings(for: facts, targets: targets, context: context).filter {
            targets.contains(RepoPath.relative($0.filePath, to: context.repoRoot))
        }
    }

    /// Returns one file's facts, from the cache when its content is unchanged, otherwise by parsing it.
    ///
    /// - Parameters:
    ///   - url: The file.
    ///   - context: Repo-wide state, for the repo root.
    ///   - access: Reads and parses the file.
    /// - Returns: Its facts, or `nil` for a language without module facts.
    private func facts(for url: URL, context: AnalysisContext, access: FileAccess) throws -> FileFacts? {
        let path = RepoPath.relative(url, to: context.repoRoot)
        let file = try access.read(url)
        let hash = StableHash.hex(file.contents)
        if let cached = store.cachedFacts(path: path, contentHash: hash) { return cached }
        return try access.parse(file).map { FileFacts(path: path, contentHash: hash, module: $0) }
    }
}

/// Converts between file URLs and repo-relative paths with `/` separators, on every platform.
public enum RepoPath {
    /// Expresses a file's location relative to the repo root.
    ///
    /// - Parameters:
    ///   - url: The file.
    ///   - root: The repo root.
    /// - Returns: The relative path with `/` separators, or the full path if it's outside the root.
    public static func relative(_ url: URL, to root: URL) -> String {
        let file = url.standardizedFileURL.pathComponents
        let base = root.standardizedFileURL.pathComponents
        guard file.starts(with: base) else { return file.joined(separator: "/") }
        return file.dropFirst(base.count).joined(separator: "/")
    }

    /// Resolves a repo-relative path to a file URL.
    ///
    /// - Parameters:
    ///   - path: The repo-relative path.
    ///   - root: The repo root.
    /// - Returns: The file's URL.
    public static func url(_ path: String, in root: URL) -> URL {
        path.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
    }
}
