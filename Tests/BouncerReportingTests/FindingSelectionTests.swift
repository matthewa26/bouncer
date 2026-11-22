import XCTest
import Foundation
import BouncerCore
import BouncerReporting

final class FindingSelectionTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")

    private func finding(_ rule: String, _ path: String, _ line: Int, _ severity: Severity = .warning) -> Finding {
        Finding(ruleID: rule, severity: severity, filePath: root.appendingPathComponent(path), line: line, message: "m")
    }

    private func apply(_ selection: FindingSelection, to findings: [Finding]) -> SelectedFindings {
        selection.apply(to: AnalysisResult(findings: findings, coverage: nil), repoRoot: root)
    }

    private var sample: [Finding] {
        [
            finding("magic-number", "Sources/B.swift", 3),
            finding("long-lines", "Tests/T.swift", 1, .info),
            finding("force-unwrap", "Sources/A.swift", 7, .error),
            finding("magic-number", "Sources/A.swift", 2),
            finding("long-lines", "Sources/A.swift", 7)
        ]
    }

    func testWithoutFiltersOrPagingTheResultIsUntouched() {
        let selected = apply(FindingSelection(), to: sample)
        XCTAssertFalse(FindingSelection().isActive)
        XCTAssertEqual(selected.matching.findings, sample)
        XCTAssertEqual(selected.page.findings, sample)
        XCTAssertNil(selected.nextOffset)
    }

    func testFiltersByRepeatedRules() {
        var selection = FindingSelection()
        selection.rules = ["magic-number", "force-unwrap"]
        let lines = apply(selection, to: sample).matching.findings.map { "\($0.ruleID):\($0.line)" }
        XCTAssertEqual(lines, ["magic-number:2", "force-unwrap:7", "magic-number:3"])
    }

    func testFiltersByPathGlobsRelativeToTheRepoRoot() {
        var selection = FindingSelection()
        selection.paths = ["Tests/**", "Sources/B.swift"]
        let paths = apply(selection, to: sample).matching.findings.map { RepoPath.relative($0.filePath, to: root) }
        XCTAssertEqual(paths, ["Sources/B.swift", "Tests/T.swift"])
    }

    func testFiltersByMinimumSeverity() {
        var selection = FindingSelection()
        selection.minimumSeverity = .warning
        let selected = apply(selection, to: sample)
        XCTAssertEqual(selected.matching.findings.count, 4)
        XCTAssertEqual(selected.totalCount, 5)
        XCTAssertFalse(selected.matching.findings.contains { $0.severity == .info })
    }

    func testPagesInFileLineRuleOrder() {
        var selection = FindingSelection()
        selection.limit = 2
        selection.offset = 1
        let selected = apply(selection, to: sample)
        XCTAssertEqual(selected.page.findings.map { "\($0.ruleID):\($0.line)" }, ["force-unwrap:7", "long-lines:7"])
        XCTAssertEqual(selected.matching.findings.count, 5)
        XCTAssertEqual(selected.offset, 1)
        XCTAssertEqual(selected.nextOffset, 3)
    }

    func testTheExitCodeSetIsTheFilteredFindingsNotThePage() {
        var selection = FindingSelection()
        selection.minimumSeverity = .warning
        selection.limit = 1
        let selected = apply(selection, to: sample)
        XCTAssertFalse(selected.page.findings.contains { $0.severity >= .error })
        XCTAssertTrue(selected.matching.findings.contains { $0.severity >= .error })
        selection.rules = ["magic-number"]
        XCTAssertFalse(apply(selection, to: sample).matching.findings.contains { $0.severity >= .error })
    }

    func testAZeroLimitShowsNothingButCountsEverything() {
        var selection = FindingSelection()
        selection.limit = 0
        let selected = apply(selection, to: sample)
        XCTAssertTrue(selected.page.findings.isEmpty)
        XCTAssertEqual(selected.matching.findings.count, 5)
        XCTAssertNil(selected.nextOffset)
    }
}
