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
