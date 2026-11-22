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

    /// Fingerprints a file for duplicate-code detection, which works on text rather than module facts.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - cached: Fingerprints cached for the file's current contents, reusable if their scheme still matches.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The fingerprints, or `nil` when no rule needs them.
    func cloneFacts(for file: SourceFile, cached: CloneFacts?, context: AnalysisContext) -> CloneFacts?
}

extension ProjectAnalyzer {
    /// Analyzers without text-based rules compute no fingerprints.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - cached: Unused.
    ///   - context: Unused.
    /// - Returns: `nil`.
    public func cloneFacts(for file: SourceFile, cached: CloneFacts?, context: AnalysisContext) -> CloneFacts? {
        nil
    }
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

    /// Reads and parses files for the project phase, and the facts already parsed for target files.
    struct FileAccess {
        let read: (URL) throws -> SourceFile
        let parse: (SourceFile) throws -> ModuleFacts?
        /// Target files' facts from the main pass, keyed by repo-relative path, so they aren't parsed twice.
        var parsed: [String: FileFacts] = [:]
        /// Target files as the main pass read them, keyed by repo-relative path, so they aren't read twice.
        var sources: [String: SourceFile] = [:]
        /// Target files' content hashes from the main pass, keyed by repo-relative path, so they aren't hashed twice.
        var hashes: [String: String] = [:]
        /// Receives the phase's progress events.
        var onEvent: AnalysisEventHandler = { _ in }
    }

    /// Counts where the index's facts came from, for the run log.
    struct FactsTally: Equatable {
        /// Files whose facts the main pass had already extracted.
        var reused = 0
        /// Files whose facts the cache still held for their current contents.
        var cached = 0
        /// Files parsed afresh.
        var parsed = 0

        /// Counts one file by the first place that had its facts.
        ///
        /// - Parameters:
        ///   - reused: The main pass's facts for it, if any.
        ///   - cached: The cache's facts for it, if any.
        mutating func record(reused: FileFacts?, cached: FileFacts?) {
            if reused != nil { self.reused += 1 } else if cached != nil { self.cached += 1 } else { parsed += 1 }
        }

        /// The tally as a log note.
        var note: String {
            "project index: \(reused) reused from the main pass, \(cached) from the facts cache, \(parsed) parsed"
        }
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
        let urls = try AnalysisPhase.listProjectFiles.run(emit: access.onEvent) { try indexProvider.targetFiles() }
        let facts = try AnalysisPhase.projectIndex.run(total: urls.count, emit: access.onEvent) {
            try index(urls, context: context, access: access)
        }
        return AnalysisPhase.projectRules.run(emit: access.onEvent) {
            analyzer.findings(for: facts, targets: targets, context: context).filter {
                targets.contains(RepoPath.relative($0.filePath, to: context.repoRoot))
            }
        }
    }

    /// Gathers every listed file's facts and saves them to the cache, noting where they came from.
    ///
    /// - Parameters:
    ///   - urls: The files to index.
    ///   - context: Repo-wide state.
    ///   - access: Reads and parses the files.
    /// - Returns: The indexed facts.
    /// - Throws: If a file can't be read or parsed, or the cache can't be saved.
    private func index(_ urls: [URL], context: AnalysisContext, access: FileAccess) throws -> [FileFacts] {
        var tally = FactsTally()
        let facts = try urls.compactMap { url in
            try AnalysisEvent.timingFile(url, emit: access.onEvent) {
                (try self.facts(for: url, context: context, access: access, tally: &tally), 0)
            }
        }
        access.onEvent(.note(tally.note))
        try store.save(facts)
        return facts
    }

    /// Returns one file's facts, from the main pass or the cache when possible, otherwise by parsing it,
    /// with duplicate-code fingerprints that are likewise reused from the cache while still valid.
    ///
    /// - Parameters:
    ///   - url: The file.
    ///   - context: Repo-wide state, for the repo root and the project rules' settings.
    ///   - access: Reads and parses the file.
    ///   - tally: Counts where the facts came from.
    /// - Returns: Its facts, or `nil` for a binary file or a language without module facts.
    /// - Throws: If the file can't be read or parsed.
    private func facts(
        for url: URL, context: AnalysisContext, access: FileAccess, tally: inout FactsTally
    ) throws -> FileFacts? {
        let path = RepoPath.relative(url, to: context.repoRoot)
        guard let file = try access.sources[path] ?? Self.readText(url, access: access) else { return nil }
        let hash = access.parsed[path]?.contentHash ?? access.hashes[path] ?? StableHash.hex(file.contents)
        let cached = store.cachedFacts(path: path, contentHash: hash)
        tally.record(reused: access.parsed[path], cached: cached)
        let fresh = { try access.parse(file).map { FileFacts(path: path, contentHash: hash, module: $0) } }
        guard let base = try access.parsed[path] ?? cached ?? fresh() else { return nil }
        return base.with(clones: analyzer.cloneFacts(for: file, cached: cached?.clones, context: context))
    }

    /// Reads a file for the index, skipping binary files.
    ///
    /// - Parameters:
    ///   - url: The file.
    ///   - access: Reads files.
    /// - Returns: The file, or `nil` if it's binary.
    /// - Throws: If the file can't be read.
    private static func readText(_ url: URL, access: FileAccess) throws -> SourceFile? {
        do { return try access.read(url) } catch FileContentsError.binary { return nil }
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
