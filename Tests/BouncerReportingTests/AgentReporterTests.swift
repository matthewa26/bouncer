import XCTest
import Foundation
import BouncerCore
@testable import BouncerReporting

final class AgentReporterTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")

    private func finding(_ rule: String, _ path: String, _ line: Int, _ message: String = "m") -> Finding {
        Finding(ruleID: rule, severity: .warning, filePath: root.appendingPathComponent(path), line: line, message: message)
    }

    private func report(_ findings: [Finding], grouping: ReportGrouping = .file, selection: SelectedFindings? = nil) -> String {
        AgentReporter(repoRoot: root, grouping: grouping, selection: selection)
            .report(AnalysisResult(findings: findings, coverage: nil), verbosity: .normal)
    }

    func testGroupsByFileWithRelativePathsInFileLineRuleOrder() {
        let output = report([
            finding("b-rule", "Sources/B.swift", 4, "x"),
            finding("magic-number", "Sources/A.swift", 9, "y"),
            finding("long-lines", "Sources/A.swift", 2, "z"),
            finding("force-unwrap", "Sources/A.swift", 9, "w")
        ])
        XCTAssertEqual(output, """
        Sources/A.swift
          2 long-lines z
          9 force-unwrap w
          9 magic-number y
        Sources/B.swift
          4 b-rule x
        4 findings.
        """)
    }

    func testOmitsAMessageThatRepeatsThePreviousOneForItsRule() {
        let output = report([
            finding("force-unwrap", "A.swift", 1, "Force unwrap."),
            finding("magic-number", "A.swift", 2, "Force unwrap."),
            finding("force-unwrap", "A.swift", 3, "Force unwrap."),
            finding("force-unwrap", "B.swift", 1, "Force unwrap."),
            finding("force-unwrap", "B.swift", 2, "Other."),
            finding("force-unwrap", "B.swift", 3, "Force unwrap.")
        ])
        XCTAssertEqual(output.split(separator: "\n").map(String.init), [
            "A.swift", "  1 force-unwrap Force unwrap.", "  2 magic-number Force unwrap.", "  3 force-unwrap",
            "B.swift", "  1 force-unwrap", "  2 force-unwrap Other.", "  3 force-unwrap Force unwrap.",
            "6 findings."
        ])
    }

    func testGroupsByRuleAsPathLineMessage() {
        let output = report([
            finding("magic-number", "B.swift", 5, "Magic."),
            finding("long-lines", "A.swift", 1, "Long."),
            finding("magic-number", "A.swift", 3, "Magic.")
        ], grouping: .rule)
        XCTAssertEqual(output, """
        long-lines
          A.swift:1 Long.
        magic-number
          A.swift:3 Magic.
          B.swift:5
        3 findings.
        """)
    }

    func testHasNoColorOrJSONAndFlattensMultilineMessages() {
        let output = report([finding("r", "A.swift", 1, "first\nsecond")])
        XCTAssertFalse(output.contains("\u{1B}"))
        XCTAssertFalse(output.contains("{"))
        XCTAssertTrue(output.contains("  1 r first second"))
    }

    func testFooterForACleanRunAndASingleFinding() {
        XCTAssertEqual(report([]), "No findings.")
        XCTAssertEqual(report([finding("r", "A.swift", 1)]).split(separator: "\n").last, "1 finding.")
    }

    func testFooterNamesThePageTheFilterTotalAndTheNextOffset() {
        let findings = (1...5).map { finding("r", "A.swift", $0) } + [finding("other", "A.swift", 9)]
        var selection = FindingSelection()
        selection.rules = ["r"]
        selection.limit = 2
        selection.offset = 1
        let selected = selection.apply(to: AnalysisResult(findings: findings, coverage: nil), repoRoot: root)
        let output = report(selected.page.findings, selection: selected)
        XCTAssertEqual(output, """
        A.swift
          2 r m
          3 r
        Showing 2-3 of 5 findings (6 before filters). Next: --offset 3
        """)
    }

    func testFooterOnTheLastPageHasNoNextOffset() {
        var selection = FindingSelection()
        selection.limit = 2
        selection.offset = 2
        let findings = (1...3).map { finding("r", "A.swift", $0) }
        let selected = selection.apply(to: AnalysisResult(findings: findings, coverage: nil), repoRoot: root)
        XCTAssertEqual(AgentReporter.footer(selected), "Showing 3-3 of 3 findings.")
    }

    func testFooterPastTheEndSaysNoneAreShown() {
        var selection = FindingSelection()
        selection.offset = 10
        let findings = (1...3).map { finding("r", "A.swift", $0) }
        let selected = selection.apply(to: AnalysisResult(findings: findings, coverage: nil), repoRoot: root)
        XCTAssertEqual(AgentReporter.footer(selected), "None of 3 findings at offset 3.")
    }
}
