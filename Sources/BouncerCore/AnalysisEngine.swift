import Foundation

/// Runs every configured analyzer over a set of target files and produces one result.
///
/// This is the composition root's product: everything it touches (which
/// files to look at, how to analyze each language, whether to check coverage)
/// arrives as an injected protocol, so the engine itself never knows
/// whether it's running against git-staged files or a full repo walk.
public struct AnalysisEngine: Sendable {
    /// Coverage checking configuration for one `AnalysisEngine` run.
    public struct CoverageConfiguration: Sendable {
        public let provider: CoverageProvider
        public let reportPath: URL
        public let threshold: Double

        /// Creates a coverage configuration.
        ///
        /// - Parameters:
        ///   - provider: The provider that can parse `reportPath`.
        ///   - reportPath: The coverage report's location on disk.
        ///   - threshold: The minimum acceptable line coverage percentage.
        public init(provider: CoverageProvider, reportPath: URL, threshold: Double) {
            self.provider = provider
            self.reportPath = reportPath
            self.threshold = threshold
        }
    }

    private let fileProvider: TargetFileProvider
    private let contentsProvider: FileContentsProvider
    private let knownAnalyzers: [Language: LanguageAnalyzer]
    private let fallbackAnalyzer: LanguageAnalyzer
    private let context: AnalysisContext
    private let baseline: Baseline
    private let coverage: CoverageConfiguration?
    private let project: ProjectPhase?
    private let change: ChangeAnalyzer?

    /// Creates an analysis engine from its fully-resolved dependencies.
    ///
    /// - Parameters:
    ///   - fileProvider: Supplies the files to analyze.
    ///   - contentsProvider: Reads each file's contents.
    ///   - knownAnalyzers: An analyzer for each language that has a dedicated one.
    ///   - fallbackAnalyzer: Used for any language without an entry in `knownAnalyzers`.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    ///   - baseline: Previously accepted findings to exclude from the result.
    ///   - coverage: Coverage checking configuration, or `nil` to skip it.
    ///   - project: The project pass (import cycles, unused exports, …), or `nil` to skip it.
    ///   - change: The change rules (oversized diff, complexity ratchet), or `nil` to skip them.
    public init(
        fileProvider: TargetFileProvider,
        contentsProvider: FileContentsProvider,
        knownAnalyzers: [Language: LanguageAnalyzer],
        fallbackAnalyzer: LanguageAnalyzer,
        context: AnalysisContext,
        baseline: Baseline = .empty,
        coverage: CoverageConfiguration? = nil,
        project: ProjectPhase? = nil,
        change: ChangeAnalyzer? = nil
    ) {
        self.fileProvider = fileProvider
        self.contentsProvider = contentsProvider
        self.knownAnalyzers = knownAnalyzers
        self.fallbackAnalyzer = fallbackAnalyzer
        self.context = context
        self.baseline = baseline
        self.coverage = coverage
        self.project = project
        self.change = change
    }

    /// The reported findings, split by the pass they came from, with each target file's record.
    private struct Reported {
        /// Each analyzed target file's record.
        let records: [FileRecord]
        /// The per-file pass's reported findings, in file order.
        let fileFindings: [Finding]
        /// The later passes' reported findings.
        let later: [Finding]
    }

    /// Receives the run's progress events, in order and one at a time, though not always on the calling thread
    /// (see `AnalysisEvent`); does nothing unless set.
    public var onEvent: AnalysisEventHandler = { _ in }

    /// The default for `jobs`: one per active processor core.
    public static var defaultJobs: Int { ProcessInfo.processInfo.activeProcessorCount }

    /// How many files the main pass, a saved run's re-checks, and the project index analyze at once; one
    /// analyzes them in turn on the calling thread. Values below one are taken as one. The results are the same,
    /// in the same order, at any setting.
    public var jobs = AnalysisEngine.defaultJobs {
        didSet { jobs = max(1, jobs) }
    }

    /// An earlier run whose per-file findings `runRecordingFiles()` reuses for files that haven't changed, or
    /// `nil` to analyze every file.
    public var priorRun: PriorRun?

    /// Whether this run stamps and hashes each file and reuses `priorRun`'s findings; set by `runRecordingFiles()`.
    private var recordsFiles = false

    /// The main pass, configured from this engine.
    private var filePass: FilePass {
        var pass = FilePass(
            fileProvider: fileProvider, contentsProvider: contentsProvider, knownAnalyzers: knownAnalyzers,
            fallbackAnalyzer: fallbackAnalyzer, context: context
        )
        (pass.extractsFacts, pass.recordsFiles) = (project != nil, recordsFiles)
        (pass.priorRun, pass.onEvent, pass.jobs) = (priorRun, onEvent, jobs)
        return pass
    }

    /// Analyzes every target file, runs the project pass and change rules, and checks coverage, if configured.
    ///
    /// - Returns: The combined findings and coverage report.
    /// - Throws: If a file can't be read, an analyzer fails, or coverage can't be parsed.
    public func run() throws -> AnalysisResult {
        try serializingEvents.execute().result
    }

    /// This engine with its event handler made to take turns, since parallel workers report their files at once.
    private var serializingEvents: AnalysisEngine {
        var engine = self
        if jobs > 1 { engine.onEvent = AnalysisEvent.serialized(onEvent) }
        return engine
    }

    /// Runs like `run()`, but also records each target file's stamp, content hash, and per-file findings for a
    /// saved run, and reuses `priorRun`'s findings for files whose contents haven't changed.
    ///
    /// - Returns: The result, with each target file's record.
    /// - Throws: If a file can't be read, an analyzer fails, or coverage can't be parsed.
    public func runRecordingFiles() throws -> RecordedRun {
        var recording = serializingEvents
        recording.recordsFiles = true
        return try recording.execute()
    }

    /// Runs every pass, recording each target file's stamp and hash when `recordsFiles` is set.
    ///
    /// - Returns: The result, with each target file's record.
    /// - Throws: If a file can't be read, an analyzer fails, or coverage can't be parsed.
    private func execute() throws -> RecordedRun {
        let urls = try AnalysisPhase.discoverFiles.run(emit: onEvent) { try fileProvider.targetFiles() }
        let analyzed = try analyzeFiles(urls)
        let baselined = AnalysisPhase.baseline.run(emit: onEvent) { baselineMarks(analyzed) }
        let coverageReport = try loadCoverageReport()
        let later = try projectFindings(for: analyzed) + changeFindings(for: analyzed.map(\.file))
        let reported = AnalysisPhase.suppressions.run(emit: onEvent) { unsuppressed(analyzed, baselined, later) }
        let other = reported.later + coverageFindings(from: coverageReport)
        let result = AnalysisResult(findings: reported.fileFindings + other, coverage: coverageReport)
        return RecordedRun(result: result, files: reported.records, otherFindings: other)
    }

    /// Runs the main pass as a step of the run, with a file count for progress displays.
    ///
    /// - Parameter urls: The target files.
    /// - Returns: The text files and their analyses, in order.
    /// - Throws: If a file can't be read or its analyzer fails.
    private func analyzeFiles(_ urls: [URL]) throws -> [AnalyzedFile] {
        try AnalysisPhase.analyzeFiles.run(total: urls.count, emit: onEvent) { try filePass.analyzeAll(urls) }
    }

    /// Marks which of the main pass's findings the baseline accepts, noting how many it did.
    ///
    /// - Parameter analyzed: The analyzed target files.
    /// - Returns: For each file, whether the baseline accepts each of its findings.
    private func baselineMarks(_ analyzed: [AnalyzedFile]) -> [[Bool]] {
        let marks = analyzed.map { item in item.analysis.findings.map { isBaselined($0, in: item.file) } }
        let accepted = marks.reduce(0) { total, file in total + file.filter { $0 }.count }
        if accepted > 0 { onEvent(.note("the baseline accepted \(accepted) finding(s)")) }
        return marks
    }

    /// Runs the project pass, keeping non-baselined findings in the target files.
    ///
    /// - Parameter analyzed: The analyzed target files, whose facts and hashes the project pass reuses.
    /// - Returns: The project findings, or none without a project pass.
    /// - Throws: If indexing fails.
    private func projectFindings(for analyzed: [AnalyzedFile]) throws -> [Finding] {
        guard let project else { return [] }
        let access = projectAccess(for: analyzed)
        let found = try project.findings(targets: Set(access.sources.keys), context: context, access: access)
        return unbaselined(found, access.sources)
    }

    /// Gives the project pass the main pass's files, facts, and hashes, and a way to read and parse the rest.
    ///
    /// - Parameter analyzed: The analyzed target files.
    /// - Returns: The project pass's file access.
    private func projectAccess(for analyzed: [AnalyzedFile]) -> ProjectPhase.FileAccess {
        let pass = filePass
        var access = ProjectPhase.FileAccess(read: pass.loadSourceFile) {
            try pass.analyzer(for: $0).moduleFacts(file: $0)
        }
        access.sources = Dictionary(analyzed.map { ($0.loaded.path, $0.file) }) { first, _ in first }
        (access.parsed, access.hashes, access.onEvent) = (parsedFacts(analyzed), contentHashes(analyzed), onEvent)
        access.jobs = jobs
        return access
    }

    /// Runs the change rules, keeping findings the baseline doesn't accept.
    ///
    /// - Parameter files: The target files.
    /// - Returns: The change findings, or none without change rules.
    private func changeFindings(for files: [SourceFile]) -> [Finding] {
        guard let change else { return [] }
        let byPath = Dictionary(files.map { (repoPath(of: $0.path), $0) }) { first, _ in first }
        let found = AnalysisPhase.changeRules.run(emit: onEvent) { change.findings(for: files, context: context) }
        return unbaselined(found, byPath)
    }

    /// Drops findings the baseline accepts or a `bouncer:disable…` comment in their file switches off, recording
    /// which of each file's own findings were dropped.
    ///
    /// - Parameters:
    ///   - analyzed: The analyzed target files.
    ///   - baselined: For each file, which of its findings the baseline accepts.
    ///   - later: The later passes' findings, already filtered by the baseline.
    /// - Returns: The reported findings, and each file's record.
    private func unsuppressed(_ analyzed: [AnalyzedFile], _ baselined: [[Bool]], _ later: [Finding]) -> Reported {
        let index = Dictionary(analyzed.map { ($0.loaded.path, Suppressions(file: $0.file)) }) { first, _ in first }
        let records = zip(analyzed, baselined).map { record($0, baselined: $1, suppressions: index) }
        let fileFindings = records.flatMap(\.reported), kept = later.filter { !isSuppressed($0, by: index) }
        let unbaselined = baselined.reduce(0) { total, file in total + file.filter { !$0 }.count }
        let dropped = unbaselined + later.count - fileFindings.count - kept.count
        if dropped > 0 { onEvent(.note("suppression comments switched off \(dropped) finding(s)")) }
        return Reported(records: records, fileFindings: fileFindings, later: kept)
    }

    /// Records one file's findings and which of them the baseline accepts or a comment suppresses.
    ///
    /// - Parameters:
    ///   - item: The analyzed file.
    ///   - baselined: Whether the baseline accepts each of its findings.
    ///   - suppressions: Each target file's suppression comments, keyed by repo-relative path.
    /// - Returns: The file's record.
    private func record(
        _ item: AnalyzedFile, baselined: [Bool], suppressions: [String: Suppressions]
    ) -> FileRecord {
        let findings = item.analysis.findings
        let hidden = findings.indices.filter { baselined[$0] || isSuppressed(findings[$0], by: suppressions) }
        return FileRecord(loaded: item.loaded, findings: findings, hidden: hidden)
    }

    /// Checks whether a comment in the file a finding lands in switches it off.
    ///
    /// - Parameters:
    ///   - finding: The finding.
    ///   - suppressions: Each target file's suppression comments; a finding in any other file is kept.
    /// - Returns: Whether the finding is suppressed.
    private func isSuppressed(_ finding: Finding, by suppressions: [String: Suppressions]) -> Bool {
        suppressions[repoPath(of: finding.filePath)]?.suppresses(finding.ruleID, at: finding.line) == true
    }

    /// Drops findings the baseline accepts, judging each by the target file it lands in.
    ///
    /// - Parameters:
    ///   - findings: Findings from a pass after the main one.
    ///   - files: The target files, keyed by repo-relative path; a finding elsewhere is kept.
    /// - Returns: The findings the baseline doesn't accept.
    private func unbaselined(_ findings: [Finding], _ files: [String: SourceFile]) -> [Finding] {
        findings.filter { finding in
            files[repoPath(of: finding.filePath)].map { !isBaselined(finding, in: $0) } ?? true
        }
    }

    /// Packages the main pass's facts for the project pass, keyed by repo-relative path.
    ///
    /// - Parameter analyzed: The analyzed target files.
    /// - Returns: Each target file's facts, for files whose analyzer extracted any.
    private func parsedFacts(_ analyzed: [AnalyzedFile]) -> [String: FileFacts] {
        let pairs = analyzed.compactMap { item -> (String, FileFacts)? in
            let hash = item.loaded.contentHash ?? StableHash.hex(item.file.contents)
            let path = item.loaded.path
            return item.analysis.facts.map { (path, FileFacts(path: path, contentHash: hash, module: $0)) }
        }
        return Dictionary(pairs) { first, _ in first }
    }

    /// Collects the main pass's content hashes, keyed by repo-relative path, so the project pass reuses them.
    ///
    /// - Parameter analyzed: The analyzed target files.
    /// - Returns: The hashes of the files that have one.
    private func contentHashes(_ analyzed: [AnalyzedFile]) -> [String: String] {
        let pairs = analyzed.compactMap { item in item.loaded.contentHash.map { (item.loaded.path, $0) } }
        return Dictionary(pairs) { first, _ in first }
    }

    /// Checks whether a finding matches an entry already accepted into the baseline.
    ///
    /// - Parameters:
    ///   - finding: The finding to check.
    ///   - file: The file the finding came from, used to read the offending line.
    /// - Returns: Whether the baseline already accepts this finding.
    private func isBaselined(_ finding: Finding, in file: SourceFile) -> Bool {
        let path = relativePath(of: finding.filePath)
        let line = lineContent(at: finding.line, in: file)
        let fingerprint = Baseline.fingerprint(ruleID: finding.ruleID, relativePath: path, lineContent: line)
        return baseline.contains(fingerprint)
    }

    /// Expresses a file path the way the project pass does: repo-relative, with `/` separators.
    ///
    /// - Parameter url: The file's absolute location.
    /// - Returns: The repo-relative path.
    private func repoPath(of url: URL) -> String {
        RepoPath.relative(url, to: context.repoRoot)
    }

    /// Expresses a path relative to the repo root, for baseline fingerprints.
    ///
    /// - Parameter url: The absolute path.
    /// - Returns: The path relative to the repo root.
    private func relativePath(of url: URL) -> String {
        let root = context.repoRoot.path
        guard url.path.hasPrefix(root) else { return url.path }
        return String(url.path.dropFirst(root.count + 1))
    }

    /// Reads the text of one line from a file, or an empty string out of range.
    ///
    /// - Parameters:
    ///   - line: The 1-indexed line number.
    ///   - file: The file to read from.
    /// - Returns: The line's text, or `""` if `line` is out of range.
    private func lineContent(at line: Int, in file: SourceFile) -> String {
        guard line >= 1, line <= file.lines.count else { return "" }
        return String(file.lines[line - 1])
    }

    /// Parses the configured coverage report, if coverage checking is enabled.
    ///
    /// - Returns: The parsed report, or `nil` if coverage isn't configured.
    /// - Throws: If the report exists but can't be parsed.
    private func loadCoverageReport() throws -> CoverageReport? {
        guard let coverage else { return nil }
        return try AnalysisPhase.coverage.run(emit: onEvent) {
            try coverage.provider.parse(reportPath: coverage.reportPath)
        }
    }

    /// Builds the synthetic coverage-threshold finding, if coverage is below threshold.
    ///
    /// - Parameter report: The parsed coverage report, if any.
    /// - Returns: A single finding, or an empty array.
    private func coverageFindings(from report: CoverageReport?) -> [Finding] {
        guard let report, let coverage else { return [] }
        let finding = CoverageThresholdChecker.evaluate(
            report: report, threshold: coverage.threshold, repoRoot: context.repoRoot
        )
        return finding.map { [$0] } ?? []
    }
}
