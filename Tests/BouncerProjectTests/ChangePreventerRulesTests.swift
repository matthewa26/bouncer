import XCTest
import Foundation
import BouncerCore
import BouncerGit
@testable import BouncerProject

/// A fixed history for the change-preventer rules.
private struct PlantedHistory: HistorySource {
    let commits: [GitCommit]
    func commits(in repoRoot: URL, days: Int) -> [GitCommit]? { commits }
}

final class ChangePreventerRulesTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")
    private var day = 0

    private func commit(_ paths: [String]) -> GitCommit {
        day += 1
        return GitCommit(hash: "c\(day)", author: "a@x.io", date: Date(timeIntervalSince1970: Double(day) * 86_400),
                         changes: paths.map { GitFileChange(path: $0, added: 1, deleted: 0) })
    }

    private func facts(_ path: String, imports: [String] = []) -> FileFacts {
        FileFacts(path: path, contentHash: "h", module: ModuleFacts(imports: imports.map { ImportFact(specifier: $0, line: 1) }))
    }

    private func run(_ id: String, _ commits: [GitCommit], facts: [FileFacts], configured: Bool = true,
                     params: [String: RuleParameterValue] = [:]) -> [Finding] {
        let settings = configured
            ? [id: RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: params))] : [:]
        let context = AnalysisContext(repoRoot: root, ruleSettings: settings)
        let rules = ProjectRules(history: PlantedHistory(commits: commits))
        return rules.findings(for: facts, targets: Set(facts.map(\.path)), context: context).filter { $0.ruleID == id }
    }

    private func places(_ found: [Finding]) -> [String] {
        found.map { RepoPath.relative($0.filePath, to: root) }
    }

    // MARK: divergent-change

    private var modules: [FileFacts] {
        [facts("core/format.py"), facts("core/clock.py"), facts("billing/charge.py", imports: ["core.format"]),
         facts("search/index.py"), facts("auth/login.py"), facts("invoicing/invoice.py", imports: ["billing.charge"]),
         facts("Package.swift"), facts("tests/test_format.py")]
    }

    func testFlagsAFileThatChangesWithUnrelatedModulesForEachReason() {
        var commits: [GitCommit] = []
        for other in ["billing/charge.py", "search/index.py", "auth/login.py"] {
            commits += (0..<3).map { _ in commit(["core/format.py", other, "tests/test_format.py", "README.md"]) }
        }
        let found = run("divergent-change", commits, facts: modules)
        XCTAssertEqual(places(found), ["core/format.py"])
        XCTAssertEqual(found.first?.message, "Changed for 3 unrelated reasons over the last 365 days, judging by the "
            + "modules that changed with it: with auth/ (3 commits); with billing/ (3 commits); with search/ "
            + "(3 commits). Split it so each part changes for one reason.")
        XCTAssertTrue(run("divergent-change", commits, facts: modules, configured: false).isEmpty)
        XCTAssertTrue(run("divergent-change", commits, facts: modules, params: ["minReasons": .int(4)]).isEmpty)
    }

    func testModulesJoinedByAnImportAreOneReasonAndRareReasonsDontCount() {
        var commits = (0..<3).map { _ in commit(["core/clock.py", "billing/charge.py"]) }
        commits += (0..<3).map { _ in commit(["core/clock.py", "invoicing/invoice.py"]) }
        commits += (0..<2).map { _ in commit(["core/clock.py", "search/index.py"]) }
        commits += (0..<3).map { _ in commit(["core/clock.py", "auth/login.py", "search/index.py", "billing/charge.py",
                                              "invoicing/invoice.py"]) }
        XCTAssertTrue(run("divergent-change", commits, facts: modules).isEmpty)
    }

    func testLeavesManifestsAlone() {
        var commits: [GitCommit] = []
        for other in ["billing/charge.py", "search/index.py", "auth/login.py"] {
            commits += (0..<3).map { _ in commit(["Package.swift", other]) }
        }
        XCTAssertTrue(run("divergent-change", commits, facts: modules).isEmpty)
    }

    // MARK: shotgun-surgery

    private var spread: [String] {
        ["ui/theme.py", "web/page.py", "web/style.py", "mobile/screen.py", "mobile/style.py", "desktop/window.py",
         "desktop/style.py"]
    }

    func testFlagsFilesWhoseTypicalChangeSpreadsReportingIdenticalPartnersOnce() {
        let files = (spread + ["ui/button.py", "web/layout.py"]).map { facts($0) }
        var commits = (0..<5).map { _ in commit(spread + ["tests/test_theme.py"]) }
        commits += (0..<5).map { _ in commit(["ui/button.py", "web/layout.py"]) }
        commits.append(commit(["web/page.py"]))
        let found = run("shotgun-surgery", commits, facts: files)
        XCTAssertEqual(places(found), ["desktop/style.py", "web/page.py"])
        XCTAssertEqual(found.first?.message, "A typical change here also changes 6 other files across 4 modules (the "
            + "median of its 5 commits over the last 180 days): each change is scattered. Gather the code that "
            + "changes together, or put the shared decision behind one module. The same holds for "
            + "desktop/window.py, mobile/screen.py, mobile/style.py, ui/theme.py, web/style.py, changed in exactly "
            + "the same commits.")
        XCTAssertTrue(run("shotgun-surgery", commits, facts: files, configured: false).isEmpty)
        XCTAssertTrue(run("shotgun-surgery", commits, facts: files, params: ["minModules": .int(5)]).isEmpty)
    }

    func testIgnoresMassCommitsAndTooFewCommits() {
        let files = spread.map { facts($0) }
        let filler = (0..<30).map { "gen/file\($0).py" }
        var commits = (0..<5).map { _ in commit(spread + filler) }
        commits += (0..<4).map { _ in commit(spread) }
        XCTAssertTrue(run("shotgun-surgery", commits, facts: files).isEmpty)
    }

    func testMedianTakesTheLowerMiddle() {
        XCTAssertEqual(Median.of([]), 0)
        XCTAssertEqual(Median.of([5, 1, 3]), 3)
        XCTAssertEqual(Median.of([4, 1, 3, 2]), 2)
    }
}
