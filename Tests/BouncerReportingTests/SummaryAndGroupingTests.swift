import XCTest
import Foundation
import BouncerCore
@testable import BouncerReporting

final class SummaryAndGroupingTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")

    private func finding(_ rule: String, _ path: String, _ line: Int, _ severity: Severity = .warning) -> Finding {
        Finding(ruleID: rule, severity: severity, filePath: root.appendingPathComponent(path), line: line, message: "msg")
    }

    private func decode(_ json: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]) ?? [:]
    }

    func testFullJSONIsUnchanged() {
        let result = AnalysisResult(findings: [finding("some-rule", "a.swift", 3, .error)], coverage: nil)
        let selected = FindingSelection().apply(to: result, repoRoot: root)
        let expected = """
        {
          "findings" : [
            {
              "filePath" : "/repo/a.swift",
              "line" : 3,
              "message" : "msg",
              "ruleID" : "some-rule",
              "severity" : "error"
            }
          ]
        }
        """
        XCTAssertEqual(JSONReporter().report(selected.page, verbosity: .normal), expected)
    }

    func testSummaryJSONHasTheSummaryFieldsAndNoFindings() {
        let result = AnalysisResult(findings: [
            finding("long-function", "Sources/A.swift", 1, .error),
            finding("long-function", "Sources/B.swift", 2),
            finding("magic-number", "Sources/A.swift", 3)
        ], coverage: CoverageReport(overallLineCoveragePercent: 80))
        let json = decode(JSONReporter().summary(result, repoRoot: root, elapsed: .seconds(2)))
        XCTAssertNil(json["findings"])
        XCTAssertEqual(json["findingCount"] as? Int, 3)
        XCTAssertEqual(json["bySeverity"] as? [String: Int], ["error": 1, "warning": 2])
        XCTAssertEqual((json["topRules"] as? [[String: Any]])?.first?["name"] as? String, "long-function")
        XCTAssertEqual((json["topFiles"] as? [[String: Any]])?.first?["name"] as? String, "Sources/A.swift")
        XCTAssertEqual(json["hint"] as? String, ReportSummary.dominantRuleHint(result))
        XCTAssertEqual(json["elapsedSeconds"] as? Double, 2)
        XCTAssertEqual(json["overallLineCoveragePercent"] as? Double, 80)
    }

    func testSummaryJSONLeavesOutTheHintAndTimeWhenThereAreNone() {
        let json = decode(JSONReporter().summary(AnalysisResult(findings: [], coverage: nil), repoRoot: root))
        XCTAssertEqual(json["findingCount"] as? Int, 0)
        XCTAssertNil(json["hint"])
        XCTAssertNil(json["elapsedSeconds"])
    }

    func testConsoleWithoutGroupingIsTheFlatList() {
        let findings = [finding("r", "b.swift", 2), finding("r", "a.swift", 1)]
        let output = ConsoleReporter(grouping: nil, repoRoot: root)
            .report(AnalysisResult(findings: findings, coverage: nil), verbosity: .normal)
        XCTAssertEqual(output, "/repo/b.swift:2: [warning] r - msg\n/repo/a.swift:1: [warning] r - msg")
    }

    func testConsoleGroupsByFile() {
        let findings = [finding("r", "b.swift", 2), finding("q", "a.swift", 1, .error), finding("r", "a.swift", 4)]
        let output = ConsoleReporter(grouping: .file, repoRoot: root)
            .report(AnalysisResult(findings: findings, coverage: nil), verbosity: .normal)
        XCTAssertEqual(output, """
        a.swift
          1: [error] q - msg
          4: [warning] r - msg

        b.swift
          2: [warning] r - msg
        """)
    }

    func testConsoleGroupsByRule() {
        let findings = [finding("r", "b.swift", 2), finding("q", "a.swift", 1, .error), finding("r", "a.swift", 4)]
        let output = ConsoleReporter(grouping: .rule, repoRoot: root)
            .report(AnalysisResult(findings: findings, coverage: nil), verbosity: .normal)
        XCTAssertEqual(output, """
        q
          a.swift:1: [error] msg

        r
          a.swift:4: [warning] msg
          b.swift:2: [warning] msg
        """)
    }
}
