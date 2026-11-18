import XCTest
import Foundation
import BouncerCore
@testable import BouncerReporting

final class ConsoleReporterTests: XCTestCase {
    private func result(_ findings: [Finding]) -> AnalysisResult {
        AnalysisResult(findings: findings, coverage: nil)
    }

    private func finding(severity: Severity, line: Int = 1, message: String = "message") -> Finding {
        Finding(ruleID: "some-rule", severity: severity, filePath: URL(fileURLWithPath: "/repo/a.swift"), line: line, message: message)
    }

    func testNormalReportsOneLinePerFinding() {
        let output = ConsoleReporter().report(result([finding(severity: .warning), finding(severity: .error)]), verbosity: .normal)
        XCTAssertEqual(output.split(separator: "\n").count, 2)
    }

    func testNormalReportsNoFindingsMessageWhenClean() {
        XCTAssertEqual(ConsoleReporter().report(result([]), verbosity: .normal), "No findings.")
    }

    func testVerboseSeparatesFindingsWithBlankLines() {
        let output = ConsoleReporter().report(result([finding(severity: .warning), finding(severity: .error)]), verbosity: .verbose)
        XCTAssertTrue(output.contains("\n\n"))
    }

    func testQuietReportsOnlyThePassFailLine() {
        XCTAssertEqual(ConsoleReporter().report(result([]), verbosity: .quiet), "Passed.")
        XCTAssertEqual(ConsoleReporter().report(result([finding(severity: .error)]), verbosity: .quiet), "Failed: 1 finding(s).")
    }

    func testCondensedBreaksDownBySeverity() {
        let output = ConsoleReporter().report(
            result([finding(severity: .error), finding(severity: .error), finding(severity: .warning)]), verbosity: .condensed
        )
        XCTAssertEqual(output, "3 finding(s): 2 error, 1 warning, 0 info.")
    }

    func testNormalReportIncludesFilePathLineAndMessage() {
        let output = ConsoleReporter().report(result([finding(severity: .error, line: 42, message: "too long")]), verbosity: .normal)
        XCTAssertTrue(output.contains("a.swift:42"))
        XCTAssertTrue(output.contains("some-rule"))
        XCTAssertTrue(output.contains("too long"))
    }
}
