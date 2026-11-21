import XCTest
import Foundation
import BouncerCore
@testable import BouncerReporting

final class JSONReporterTests: XCTestCase {
    private func decode(_ json: String) -> [String: Any] {
        let data = json.data(using: .utf8)!
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func finding(severity: Severity) -> Finding {
        Finding(ruleID: "some-rule", severity: severity, filePath: URL(fileURLWithPath: "/repo/a.swift"), line: 3, message: "msg")
    }

    func testFullReportIncludesEveryFindingRegardlessOfVerbosity() {
        let result = AnalysisResult(findings: [finding(severity: .error)], coverage: CoverageReport(overallLineCoveragePercent: 75))
        let json = decode(JSONReporter().report(result, verbosity: .quiet))
        let findings = json["findings"] as? [[String: Any]]
        XCTAssertEqual(findings?.count, 1)
        XCTAssertEqual(findings?.first?["ruleID"] as? String, "some-rule")
        XCTAssertEqual(json["overallLineCoveragePercent"] as? Double, 75)
    }

    func testCondensedReportSummarizesBySeverity() {
        let result = AnalysisResult(findings: [finding(severity: .error), finding(severity: .error)], coverage: nil)
        let json = decode(JSONReporter().report(result, verbosity: .condensed))
        XCTAssertEqual(json["violationCount"] as? Int, 2)
        let bySeverity = json["bySeverity"] as? [String: Int]
        XCTAssertEqual(bySeverity?["error"], 2)
        XCTAssertNil(json["findings"])
    }

    func testOutputIsValidJson() {
        let result = AnalysisResult(findings: [finding(severity: .warning)], coverage: nil)
        let output = JSONReporter().report(result, verbosity: .normal)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: output.data(using: .utf8)!))
    }
}

final class JSONReporterOWASPTests: XCTestCase {
    /// The exact output `--format json` printed for these findings before OWASP tagging existed.
    private let untaggedBaseline = """
        {
          "findings" : [
            {
              "filePath" : "/repo/a.swift",
              "line" : 3,
              "message" : "Function is too long.",
              "ruleID" : "long-function",
              "severity" : "warning"
            },
            {
              "filePath" : "/repo/b.py",
              "line" : 7,
              "message" : "Custom check.",
              "ruleID" : "my-custom-rule",
              "severity" : "error"
            }
          ],
          "overallLineCoveragePercent" : 75
        }
        """

    private func finding(_ ruleID: String, _ path: String, _ line: Int, _ message: String, _ severity: Severity)
        -> Finding {
        Finding(ruleID: ruleID, severity: severity, filePath: URL(fileURLWithPath: path), line: line, message: message)
    }

    func testUnmappedFindingsSerializeExactlyAsBeforeOWASPTagging() {
        let result = AnalysisResult(findings: [
            finding("long-function", "/repo/a.swift", 3, "Function is too long.", .warning),
            finding("my-custom-rule", "/repo/b.py", 7, "Custom check.", .error)
        ], coverage: CoverageReport(overallLineCoveragePercent: 75))
        XCTAssertEqual(JSONReporter().report(result, verbosity: .normal), untaggedBaseline)
    }
}

extension JSONReporterOWASPTests {
    func testMappedFindingsCarryTheirOWASPCategory() {
        let result = AnalysisResult(findings: [
            finding("sql-string-building", "/repo/c.ts", 2, "SQL built by concatenation.", .warning)
        ], coverage: nil)
        let expected = """
            {
              "findings" : [
                {
                  "filePath" : "/repo/c.ts",
                  "line" : 2,
                  "message" : "SQL built by concatenation.",
                  "owasp" : "A05:2025",
                  "ruleID" : "sql-string-building",
                  "severity" : "warning"
                }
              ]
            }
            """
        XCTAssertEqual(JSONReporter().report(result, verbosity: .normal), expected)
    }
}
