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
    public init(
        fileProvider: TargetFileProvider,
        contentsProvider: FileContentsProvider,
        knownAnalyzers: [Language: LanguageAnalyzer],
        fallbackAnalyzer: LanguageAnalyzer,
        context: AnalysisContext,
        baseline: Baseline = .empty,
        coverage: CoverageConfiguration? = nil,
        project: ProjectPhase? = nil
    ) {
        self.fileProvider = fileProvider
        self.contentsProvider = contentsProvider
        self.knownAnalyzers = knownAnalyzers
        self.fallbackAnalyzer = fallbackAnalyzer
        self.context = context
        self.baseline = baseline
        self.coverage = coverage
        self.project = project
    }

    /// Analyzes every target file, runs the project pass, and checks coverage, if configured.
    ///
    /// - Returns: The combined findings and coverage report.
    /// - Throws: If a file can't be read, an analyzer fails, or coverage can't be parsed.
    public func run() throws -> AnalysisResult {
        let files = try fileProvider.targetFiles().map(loadSourceFile)
        let analyses = try files.map(analyze)
        let findings = zip(files, analyses).flatMap { file, analysis in
            analysis.findings.filter { !isBaselined($0, in: file) }
        }
        let coverageReport = try loadCoverageReport()
        let all = findings + (try projectFindings(for: files, analyses: analyses))
        return AnalysisResult(findings: all + coverageFindings(from: coverageReport), coverage: coverageReport)
    }

    /// Analyzes one file, also extracting its module facts in the same parse when the project pass will run.
    ///
    /// - Parameter file: The file to analyze.
    /// - Returns: The file's findings, and its facts if the project pass needs them.
    /// - Throws: If its analyzer fails.
    private func analyze(_ file: SourceFile) throws -> FileAnalysis {
        let analyzer = analyzer(for: file)
        guard project != nil else {
            return FileAnalysis(findings: try analyzer.analyze(file: file, context: context), facts: nil)
        }
        return try analyzer.analyzeWithFacts(file: file, context: context)
    }

    /// Runs the project pass, keeping non-baselined findings in the target files.
    ///
    /// - Parameters:
    ///   - files: The target files.
    ///   - analyses: Their analyses, whose facts the project pass reuses instead of parsing again.
    /// - Returns: The project findings, or none without a project pass.
    /// - Throws: If indexing fails.
    private func projectFindings(for files: [SourceFile], analyses: [FileAnalysis]) throws -> [Finding] {
        guard let project else { return [] }
        let byPath = Dictionary(files.map { (repoPath(of: $0.path), $0) }) { first, _ in first }
        var access = ProjectPhase.FileAccess(read: loadSourceFile) { try analyzer(for: $0).moduleFacts(file: $0) }
        access.parsed = parsedFacts(files: files, analyses: analyses)
        access.sources = byPath
        return try project.findings(targets: Set(byPath.keys), context: context, access: access).filter { finding in
            let file = byPath[repoPath(of: finding.filePath)]
            return file.map { !isBaselined(finding, in: $0) } ?? true
        }
    }

    /// Packages the main pass's facts for the project pass, keyed by repo-relative path.
    ///
    /// - Parameters:
    ///   - files: The target files.
    ///   - analyses: Their analyses.
    /// - Returns: Each target file's facts, for files whose analyzer extracted any.
    private func parsedFacts(files: [SourceFile], analyses: [FileAnalysis]) -> [String: FileFacts] {
        let pairs = zip(files, analyses).compactMap { file, analysis -> (String, FileFacts)? in
            let path = repoPath(of: file.path)
            let hash = StableHash.hex(file.contents)
            return analysis.facts.map { (path, FileFacts(path: path, contentHash: hash, module: $0)) }
        }
        return Dictionary(pairs) { first, _ in first }
    }

    /// Picks the analyzer for a file's language.
    ///
    /// - Parameter file: The file.
    /// - Returns: Its language's analyzer, or the fallback.
    private func analyzer(for file: SourceFile) -> LanguageAnalyzer {
        knownAnalyzers[file.language] ?? fallbackAnalyzer
    }

    /// Reads a file from disk and detects its language from its extension.
    ///
    /// - Parameter url: The file's location.
    /// - Returns: The loaded source file.
    /// - Throws: If the file can't be read.
    private func loadSourceFile(_ url: URL) throws -> SourceFile {
        let contents = try contentsProvider.contents(of: url)
        let language = Language.from(fileExtension: url.pathExtension)
        return SourceFile(path: url, language: language, contents: contents)
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
        return try coverage.provider.parse(reportPath: coverage.reportPath)
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
