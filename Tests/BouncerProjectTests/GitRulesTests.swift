import XCTest
import Foundation
import BouncerCore
import BouncerGit
@testable import BouncerProject

/// A fixed history.
private struct FixedHistory: HistorySource {
    let commits: [GitCommit]
    func commits(in repoRoot: URL, days: Int) -> [GitCommit]? { commits }
}

/// Measures a file by looking up its contents: each line `name complexity [lines]` is one function.
private struct ListedMeasures: FunctionMeasuring {
    func functions(in file: SourceFile) -> [FunctionMeasure]? {
        guard file.path.pathExtension != "md" else { return nil }
        return file.lines.enumerated().compactMap { offset, line in
            let parts = line.split(separator: " ")
            guard parts.count >= 2, let complexity = Int(parts[1]) else { return nil }
            let name = parts[0] == "_" ? nil : String(parts[0])
            return FunctionMeasure(name: name, line: offset + 1, complexity: complexity,
                                   logicalLines: parts.count > 2 ? Int(parts[2]) : nil)
        }
    }
}

/// A fixed staged diff and base branch.
private struct FixedChanges: ChangeSource {
    var staged: [GitFileChange] = []
    var base: (ref: String, commit: String)? = ("main", "0123456789abcdef")
    var files: [String: String] = [:]
    func stagedChanges(in repoRoot: URL) -> [GitFileChange]? { staged }
    func mergeBase(of refs: [String], in repoRoot: URL) -> (ref: String, commit: String)? {
        base.map { (refs.first ?? $0.ref, $0.commit) }
    }
    func contents(of path: String, at commit: String, in repoRoot: URL) -> String? { files[path] }
}

final class GitRulesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("git-rules-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func commit(_ day: Int, _ paths: [String], by author: String = "a@x.io") -> GitCommit {
        GitCommit(hash: "c\(day)-\(paths.count)", author: author, date: Date(timeIntervalSince1970: Double(day) * 86_400),
                  changes: paths.map { GitFileChange(path: $0, added: 1, deleted: 0) })
    }

    private func write(_ path: String, _ contents: String) throws {
        let url = RepoPath.url(path, in: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func facts(_ path: String, _ imports: [String] = []) -> FileFacts {
        FileFacts(path: path, contentHash: "h", module: ModuleFacts(imports: imports.map { ImportFact(specifier: $0, line: 1) }))
    }

    private func run(
        _ commits: [GitCommit], facts: [FileFacts], targets: Set<String>, settings: [String: RuleSettings] = [:]
    ) -> [Finding] {
        let rules = ProjectRules(history: FixedHistory(commits: commits), measurer: ListedMeasures())
        return rules.findings(for: facts, targets: targets, context: AnalysisContext(repoRoot: root, ruleSettings: settings))
    }

    private func settings(_ id: String, _ values: [String: RuleParameterValue] = [:]) -> [String: RuleSettings] {
        [id: RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: values))]
    }

    private func relative(_ finding: Finding) -> String {
        RepoPath.relative(finding.filePath, to: root)
    }

    // MARK: hotspot

    func testRanksChurnedComplexFilesAndReportsAtTheMostComplexFunction() throws {
        try write("busy.ts", "a 20\nb 25\n")
        try write("calm.ts", "a 40\n")
        try write("simple.ts", "a 2\n")
        let commits = (1...6).map { commit($0, ["busy.ts", "simple.ts"]) } + (1...5).map { commit($0, ["calm.ts"]) }
        let found = run(commits, facts: [], targets: ["busy.ts", "calm.ts", "simple.ts"])
            .filter { $0.ruleID == "hotspot" }
        XCTAssertEqual(found.map(relative), ["busy.ts", "calm.ts"])
        XCTAssertEqual(found.first?.line, 2)
        XCTAssertEqual(found.first?.message.hasPrefix("Hotspot #1 of 2: 6 commits in the last 180 days, total complexity 45"),
                       true)
        XCTAssertTrue(found.first?.message.contains("most complex: \"b\" (25)") ?? false)
    }

    func testHotspotHonorsTopMinCommitsAndTheWindow() throws {
        try write("a.ts", "f 50\n")
        try write("b.ts", "f 70\n")
        let recent = [commit(6, ["a.ts"])] + (1...5).map { commit($0, ["a.ts", "b.ts"]) }
        let only = run(recent, facts: [], targets: ["a.ts", "b.ts"], settings: settings("hotspot", ["top": .int(1)]))
        XCTAssertEqual(only.filter { $0.ruleID == "hotspot" }.map(relative), ["b.ts"])
        let busier = run(recent, facts: [], targets: ["a.ts", "b.ts"], settings: settings("hotspot", ["minCommits": .int(6)]))
        XCTAssertEqual(busier.filter { $0.ruleID == "hotspot" }.map(relative), ["a.ts"])
        let stale = [commit(400, ["a.ts"])] + (1...5).map { commit($0, ["a.ts", "b.ts"]) }
        let windowed = settings("hotspot", ["sinceDays": .int(30), "minCommits": .int(2)])
        XCTAssertTrue(run(stale, facts: [], targets: ["a.ts", "b.ts"], settings: windowed)
            .filter { $0.ruleID == "hotspot" }.isEmpty)
    }

    func testHotspotSkipsDocsAndUnmeasuredFiles() throws {
        try write("README.md", "f 99\n")
        let commits = (1...6).map { commit($0, ["README.md", "gone.ts"]) }
        XCTAssertTrue(run(commits, facts: [], targets: ["README.md", "gone.ts"]).filter { $0.ruleID == "hotspot" }.isEmpty)
    }

    func testHotspotSkipsGeneratedAndIgnoredFiles() throws {
        try write("gen.ts", "// Code generated by protoc. DO NOT EDIT.\nf 90\n")
        try write("vendor/lib.ts", "f 90\n")
        try write("mine.ts", "f 40\n")
        let commits = (1...6).map { commit($0, ["gen.ts", "vendor/lib.ts", "mine.ts"]) }
        let found = run(commits, facts: [], targets: ["gen.ts", "vendor/lib.ts", "mine.ts"],
                        settings: settings("hotspot", ["ignore": .stringList(["vendor/**"])]))
        XCTAssertEqual(found.filter { $0.ruleID == "hotspot" }.map(relative), ["mine.ts"])
    }

    // MARK: change-coupling

    func testFlagsFilesThatChangeTogetherWithoutAnImport() {
        let files = [facts("a.ts"), facts("b.ts"), facts("c.ts", ["./a"]), facts("d.ts")]
        let commits = (1...5).map { commit($0, ["a.ts", "b.ts", "c.ts"]) } + [commit(6, ["d.ts", "a.ts"])]
        let found = run(commits, facts: files, targets: ["a.ts", "b.ts", "c.ts", "d.ts"])
            .filter { $0.ruleID == "change-coupling" }
        XCTAssertEqual(found.map(relative), ["a.ts", "b.ts"])
        XCTAssertTrue(found.first?.message.hasPrefix("Changed together with b.ts in 5 commits (91% coupling)") ?? false)
        XCTAssertTrue(found.last?.message.hasPrefix("Changed together with c.ts in 5 commits") ?? false)
    }

    func testCouplingIgnoresMassCommitsSameModuleFilesAndFilesOutsideTheGraph() {
        let files = [facts("Sources/A/x.swift"), facts("Sources/A/y.swift"), facts("p.ts"), facts("q.ts")]
        let mass = (0..<31).map { "gen\($0).ts" }
        let commits = (1...6).map { commit($0, ["Sources/A/x.swift", "Sources/A/y.swift", "README.md"]) }
            + (1...6).map { commit($0 + 10, ["p.ts", "q.ts"] + mass) }
        let targets: Set<String> = ["Sources/A/x.swift", "Sources/A/y.swift", "p.ts", "q.ts", "README.md"]
        XCTAssertTrue(run(commits, facts: files, targets: targets).filter { $0.ruleID == "change-coupling" }.isEmpty)
    }

    func testCouplingNeedsTheMinimumRatio() {
        let files = [facts("a.ts"), facts("b.ts")]
        let commits = (1...5).map { commit($0, ["a.ts", "b.ts"]) } + (6...30).map { commit($0, ["a.ts"]) }
        let found = run(commits, facts: files, targets: ["a.ts", "b.ts"]).filter { $0.ruleID == "change-coupling" }
        XCTAssertTrue(found.isEmpty)
        let lenient = settings("change-coupling", ["minRatio": .double(0.25)])
        XCTAssertEqual(run(commits, facts: files, targets: ["a.ts", "b.ts"], settings: lenient).count, 1)
    }

    // MARK: single-author-file

    func testSingleAuthorIsOffUnlessConfigured() {
        let commits = (1...6).map { commit($0, ["a.ts"]) } + [commit(7, ["b.ts"], by: "b@x.io")]
        XCTAssertTrue(run(commits, facts: [], targets: ["a.ts"]).filter { $0.ruleID == "single-author-file" }.isEmpty)
    }

    func testFlagsFilesDominatedByOneAuthor() {
        let commits = (1...9).map { commit($0, ["a.ts", "shared.ts"]) }
            + (10...12).map { commit($0, ["shared.ts"], by: "b@x.io") } + [commit(13, ["a.ts", "README.md"])]
        let found = run(commits, facts: [], targets: ["a.ts", "shared.ts", "README.md"],
                        settings: settings("single-author-file"))
        XCTAssertEqual(found.map(relative), ["a.ts"])
        XCTAssertEqual(found.first?.message.hasPrefix("10 of 10 commits (100%) in the last 365 days are by a@x.io"), true)
    }

    func testSingleAuthorStaysQuietInAOnePersonRepository() {
        let commits = (1...9).map { commit($0, ["a.ts"]) }
        XCTAssertTrue(run(commits, facts: [], targets: ["a.ts"], settings: settings("single-author-file")).isEmpty)
    }

    func testHistoryRulesDoNothingWithoutHistory() {
        let context = AnalysisContext(repoRoot: root, ruleSettings: settings("single-author-file"))
        XCTAssertTrue(ProjectRules().findings(for: [facts("a.ts")], targets: ["a.ts"], context: context).isEmpty)
    }
}

final class ChangeRulesTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")

    private func file(_ path: String, _ contents: String) -> SourceFile {
        let url = RepoPath.url(path, in: root)
        return SourceFile(path: url, language: Language.from(fileExtension: url.pathExtension), contents: contents)
    }

    private func findings(
        _ files: [SourceFile], source: FixedChanges, staged: Bool = true, settings: [String: RuleSettings] = [:],
        exclude: [String] = []
    ) -> [Finding] {
        let rules = ChangeRules(source: source, measurer: ListedMeasures(), checksStagedDiff: staged, exclude: exclude)
        return rules.findings(for: files, context: AnalysisContext(repoRoot: root, ruleSettings: settings))
    }

    // MARK: oversized-change

    func testFlagsAnOversizedStagedChangeOnceAtItsLargestCheckedFile() {
        var source = FixedChanges(base: nil)
        source.staged = [
            GitFileChange(path: "small.ts", added: 10, deleted: 0), GitFileChange(path: "big.ts", added: 300, deleted: 95),
            GitFileChange(path: "deleted.ts", added: 0, deleted: 390), GitFileChange(path: "package-lock.json", added: 9000, deleted: 0)
        ]
        let found = findings([file("small.ts", ""), file("big.ts", "")], source: source)
        XCTAssertEqual(found.map(\.ruleID), ["oversized-change"])
        XCTAssertEqual(found.first?.filePath, RepoPath.url("big.ts", in: root))
        XCTAssertTrue(found.first?.message.hasPrefix("The staged change is 795 lines in 3 files, over the 400-line") ?? false)
    }

    func testOversizedChangeHonorsLimitsExcludesAndTheStagedMode() {
        var source = FixedChanges(base: nil)
        source.staged = [GitFileChange(path: "gen/a.ts", added: 500, deleted: 0), GitFileChange(path: "b.ts", added: 5, deleted: 0)]
        XCTAssertTrue(findings([], source: source, exclude: ["gen/**"]).isEmpty)
        XCTAssertTrue(findings([], source: source, staged: false).isEmpty)
        let manyFiles = [
            "oversized-change": RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: [
                "maxFiles": .int(1), "maxChangedLines": .int(10_000)
            ]))
        ]
        XCTAssertEqual(findings([], source: source, settings: manyFiles).first?.filePath, RepoPath.url("gen/a.ts", in: root))
    }

    // MARK: complexity-ratchet

    func testFlagsAFunctionAlreadyOverTheLimitThatGotWorse() {
        let source = FixedChanges(files: ["a.ts": "worse 12 50\nfine 3 5\ncrossed 9 30\nsame 15 60\n"])
        let now = file("a.ts", "fine 4 6\nworse 14 55\ncrossed 11 30\nsame 15 60\nnew 30 90\n")
        let found = findings([now], source: source, staged: false)
        XCTAssertEqual(found.map(\.line), [2])
        XCTAssertEqual(found.first?.message, "Function \"worse\" got worse than at origin/main (0123456): "
            + "complexity 12 → 14, over the 10 limit; 50 → 55 logical lines, over the 40-line limit.")
    }

    func testRatchetUsesTheConfiguredLimitsAndBase() {
        let source = FixedChanges(files: ["a.ts": "f 5 8\n"])
        let settings: [String: RuleSettings] = [
            "cyclomatic-complexity": RuleSettings(enabled: true, severity: .error, parameters: RuleParameters(values: ["max": .int(4)])),
            "complexity-ratchet": RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: [
                "base": .string("develop"), "maxLines": .int(100)
            ]))
        ]
        let found = findings([file("a.ts", "f 6 9\n")], source: source, staged: false, settings: settings)
        XCTAssertEqual(found.first?.message, "Function \"f\" got worse than at develop (0123456): complexity 5 → 6, over the 4 limit.")
    }

    func testRatchetSkipsNewFilesOverloadsAndUnnamedFunctionsAndRunsOnlyWithABase() {
        let source = FixedChanges(files: ["a.ts": "f 20\nf 30\n_ 20\n"])
        XCTAssertTrue(findings([file("a.ts", "f 25\n_ 40\n"), file("new.ts", "g 50\n")], source: source).isEmpty)
        let noBase = FixedChanges(base: nil, files: ["a.ts": "f 20\n"])
        XCTAssertTrue(findings([file("a.ts", "f 30\n")], source: noBase).isEmpty)
    }

    func testMatchesRepeatedNamesInOrderWhenTheCountsAgree() {
        let pairs = FunctionMatcher.pairs(
            before: [FunctionMeasure(name: "init", line: 1, complexity: 1), FunctionMeasure(name: "init", line: 9, complexity: 2)],
            after: [FunctionMeasure(name: "init", line: 3, complexity: 5), FunctionMeasure(name: "init", line: 12, complexity: 6)]
        )
        XCTAssertEqual(pairs.map { "\($0.old.complexity)→\($0.new.complexity)" }, ["1→5", "2→6"])
    }
}

final class FunctionMeasurerTests: XCTestCase {
    /// An analyzer that measures fixed functions, out of line order.
    private struct MeasuringAnalyzer: LanguageAnalyzer {
        let supportedLanguage = Language.swift
        func analyze(file: SourceFile, context: AnalysisContext) throws -> [Finding] { [] }
        func measureFunctions(file: SourceFile) throws -> [FunctionMeasure]? {
            [FunctionMeasure(name: "b", line: 9, complexity: 2), FunctionMeasure(name: "a", line: 2, complexity: 5)]
        }
    }

    func testAsksTheLanguagesAnalyzerAndSortsByLine() {
        let file = SourceFile(path: URL(fileURLWithPath: "/a.swift"), language: .swift, contents: "")
        let measured = AnalyzerFunctionMeasurer(analyzers: [.swift: MeasuringAnalyzer()]).functions(in: file)
        XCTAssertEqual(measured?.map(\.name), ["a", "b"])
    }

    func testMeasuresOnlyLanguagesWithAnAnalyzer() {
        let file = SourceFile(path: URL(fileURLWithPath: "/notes.md"), language: .other("md"), contents: "# hi\n")
        XCTAssertNil(AnalyzerFunctionMeasurer(analyzers: [:]).functions(in: file))
    }
}
