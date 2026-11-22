import Foundation

/// A target file as the main pass read it, with its analysis.
struct AnalyzedFile {
    /// The file as the main pass read it.
    let loaded: LoadedFile
    /// Its findings, and its module facts when the project pass needs them.
    let analysis: FileAnalysis
    /// Whether the findings are a prior run's, reused because the file hasn't changed.
    private(set) var reused = false

    /// The file.
    var file: SourceFile { loaded.file }

    /// Creates an analyzed file.
    ///
    /// - Parameters:
    ///   - loaded: The file as the main pass read it.
    ///   - analysis: Its analysis.
    init(loaded: LoadedFile, analysis: FileAnalysis) {
        self.loaded = loaded
        self.analysis = analysis
    }

    /// Creates a file whose findings are a prior run's.
    ///
    /// - Parameters:
    ///   - loaded: The file as the main pass read it.
    ///   - findings: The prior run's findings for it.
    init(loaded: LoadedFile, reusing findings: [Finding]) {
        self.loaded = loaded
        analysis = FileAnalysis(findings: findings, facts: nil)
        reused = true
    }
}

/// The engine's main pass: reads each target file and runs its language's analyzer over it, or reuses a prior
/// run's findings for a file that hasn't changed.
struct FilePass {
    /// Supplies the target files and any per-file rule scope.
    let fileProvider: TargetFileProvider
    /// Reads each file's contents.
    let contentsProvider: FileContentsProvider
    /// An analyzer for each language that has a dedicated one.
    let knownAnalyzers: [Language: LanguageAnalyzer]
    /// The analyzer for every other language.
    let fallbackAnalyzer: LanguageAnalyzer
    /// Repo-wide state, including every rule's resolved settings.
    let context: AnalysisContext
    /// Whether to extract module facts in the same parse, for the project pass.
    var extractsFacts = false
    /// Whether to stamp and hash each file and reuse `priorRun`'s findings.
    var recordsFiles = false
    /// The earlier run whose findings unchanged files reuse, when `recordsFiles` is set.
    var priorRun: PriorRun?
    /// Receives the pass's events.
    var onEvent: AnalysisEventHandler = { _ in }

    /// Reads and analyzes every target file, skipping binary ones, and re-analyzes reused files the prior run
    /// says may be stale.
    ///
    /// - Parameter urls: The target files.
    /// - Returns: The text files and their analyses, in order.
    /// - Throws: If a file can't be read or its analyzer fails.
    func analyzeAll(_ urls: [URL]) throws -> [AnalyzedFile] {
        let analyzed = try urls.compactMap(analyzeOne)
        let skipped = urls.count - analyzed.count
        if skipped > 0 { onEvent(.note("skipped \(skipped) binary file(s)")) }
        guard recordsFiles, let priorRun else { return analyzed }
        let reused = Set(analyzed.filter(\.reused).map(\.loaded.path))
        let check = priorRun.stale(among: analyzed.map(\.loaded), reused: reused)
        onEvent(.note(check.note))
        return try analyzed.map { check.stale.contains($0.loaded.path) ? try reanalyzed($0) : $0 }
    }

    /// Reads one target file and analyzes it, or reuses the prior run's findings for it, between its file events.
    ///
    /// - Parameter url: The file.
    /// - Returns: The file and its analysis, or `nil` if it's binary.
    /// - Throws: If the file can't be read or its analyzer fails.
    private func analyzeOne(_ url: URL) throws -> AnalyzedFile? {
        try AnalysisEvent.timingFile(url, emit: onEvent) { () throws -> (value: AnalyzedFile?, findings: Int) in
            guard let loaded = try load(url) else { return (nil, 0) }
            let reused = recordsFiles ? priorRun?.findings(for: loaded) : nil
            let item = try reused.map { AnalyzedFile(loaded: loaded, reusing: $0) } ?? analyzed(loaded)
            return (item, item.analysis.findings.count)
        }
    }

    /// Analyzes a reused file afresh, between its file events.
    ///
    /// - Parameter item: The reused file.
    /// - Returns: The file with its fresh analysis.
    /// - Throws: If its analyzer fails.
    private func reanalyzed(_ item: AnalyzedFile) throws -> AnalyzedFile {
        try AnalysisEvent.timingFile(item.file.path, emit: onEvent) { () throws -> (AnalyzedFile, Int) in
            let fresh = try analyzed(item.loaded)
            return (fresh, fresh.analysis.findings.count)
        }
    }

    /// Runs the per-file pass over a read file.
    ///
    /// - Parameter loaded: The file.
    /// - Returns: The file with its analysis.
    /// - Throws: If its analyzer fails.
    private func analyzed(_ loaded: LoadedFile) throws -> AnalyzedFile {
        let analysis = scoped(try analyze(loaded.file), to: fileProvider.ruleScope(for: loaded.file.path))
        return AnalyzedFile(loaded: loaded, analysis: analysis)
    }

    /// Reads a target file, stamping it first and hashing it when the run records its files.
    ///
    /// - Parameter url: The file.
    /// - Returns: The read file, or `nil` if it's binary.
    /// - Throws: If the file can't be read.
    private func load(_ url: URL) throws -> LoadedFile? {
        let stamp = recordsFiles ? FileStamp.read(url) : nil
        guard let file = try loadTextFile(url) else { return nil }
        let hash = recordsFiles ? StableHash.hex(file.contents) : nil
        return LoadedFile(file: file, path: repoPath(of: url), contentHash: hash, stamp: stamp)
    }

    /// Keeps only the findings of the rules a file is listed for, when its provider limits them.
    ///
    /// - Parameters:
    ///   - analysis: The file's analysis.
    ///   - rules: The rule IDs allowed to report in the file, or `nil` for every rule.
    /// - Returns: The analysis with other rules' findings dropped.
    private func scoped(_ analysis: FileAnalysis, to rules: Set<String>?) -> FileAnalysis {
        guard let rules else { return analysis }
        return FileAnalysis(findings: analysis.findings.filter { rules.contains($0.ruleID) }, facts: analysis.facts)
    }

    /// Analyzes one file, also extracting its module facts in the same parse when the project pass will run.
    ///
    /// - Parameter file: The file to analyze.
    /// - Returns: The file's findings, and its facts if the project pass needs them.
    /// - Throws: If its analyzer fails.
    private func analyze(_ file: SourceFile) throws -> FileAnalysis {
        let analyzer = analyzer(for: file)
        guard extractsFacts else {
            return FileAnalysis(findings: try analyzer.analyze(file: file, context: context), facts: nil)
        }
        return try analyzer.analyzeWithFacts(file: file, context: context)
    }

    /// Picks the analyzer for a file's language.
    ///
    /// - Parameter file: The file.
    /// - Returns: Its language's analyzer, or the fallback.
    func analyzer(for file: SourceFile) -> LanguageAnalyzer {
        knownAnalyzers[file.language] ?? fallbackAnalyzer
    }

    /// Reads a file like `loadSourceFile`, skipping binary files, which no rule applies to.
    ///
    /// - Parameter url: The file's location.
    /// - Returns: The loaded source file, or `nil` if it's binary.
    /// - Throws: If the file can't be read.
    private func loadTextFile(_ url: URL) throws -> SourceFile? {
        do { return try loadSourceFile(url) } catch FileContentsError.binary { return nil }
    }

    /// Reads a file from disk and detects its language from its extension, sniffing a `.h` header's
    /// contents to tell Objective-C from C.
    ///
    /// - Parameter url: The file's location.
    /// - Returns: The loaded source file.
    /// - Throws: If the file can't be read.
    func loadSourceFile(_ url: URL) throws -> SourceFile {
        let contents = try contentsProvider.contents(of: url)
        let language = Language.from(fileExtension: url.pathExtension, contents: contents)
        return SourceFile(path: url, language: language, contents: contents)
    }

    /// Expresses a file path the way the project pass does: repo-relative, with `/` separators.
    ///
    /// - Parameter url: The file's absolute location.
    /// - Returns: The repo-relative path.
    private func repoPath(of url: URL) -> String {
        RepoPath.relative(url, to: context.repoRoot)
    }
}
