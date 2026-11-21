import XCTest
import Foundation
import BouncerCore
@testable import BouncerReporting

final class XcodeReporterTests: XCTestCase {
    private func finding(_ severity: Severity, path: URL = URL(fileURLWithPath: "/repo/a.swift"), line: Int = 3) -> Finding {
        Finding(ruleID: "some-rule", severity: severity, filePath: path, line: line, message: "Something is off.")
    }

    private func lines(_ findings: [Finding]) -> [String] {
        XcodeReporter().report(AnalysisResult(findings: findings, coverage: nil), verbosity: .normal)
            .components(separatedBy: "\n")
    }

    func testMapsEachSeverityToAnXcodeDiagnosticKind() {
        let output = lines([finding(.error), finding(.warning), finding(.info)])
        XCTAssertEqual(output[0], "/repo/a.swift:3:1: error: Something is off. [some-rule]")
        XCTAssertEqual(output[1], "/repo/a.swift:3:1: warning: Something is off. [some-rule]")
        XCTAssertEqual(output[2], "/repo/a.swift:3:1: note: Something is off. [some-rule]")
    }

    func testRelativePathsAreMadeAbsolute() {
        let base = URL(fileURLWithPath: "/repo/project", isDirectory: true)
        let relative = URL(fileURLWithPath: "Sources/../Sources/b.swift", relativeTo: base)
        XCTAssertEqual(lines([finding(.warning, path: relative)])[0].prefix(31), "/repo/project/Sources/b.swift:3")
    }

    func testEndsWithThePlainSummaryLine() {
        let output = lines([finding(.error), finding(.warning)])
        XCTAssertEqual(output.last, "2 findings: 1 error, 1 warning.")
        XCTAssertEqual(lines([]), ["No findings."])
    }

    func testRuleIDIsTheLastBracketedSuffixAndLinesNeverWrap() {
        let multiLine = Finding(ruleID: "long-function", severity: .warning,
                                filePath: URL(fileURLWithPath: "/repo/a.swift"), line: 0, message: "first\nsecond")
        XCTAssertEqual(lines([multiLine])[0], "/repo/a.swift:1:1: warning: first second [long-function]")
    }

    func testEveryVerbosityPrintsEveryFinding() {
        let result = AnalysisResult(findings: [finding(.error)], coverage: nil)
        for verbosity in [OutputVerbosity.quiet, .condensed, .verbose] {
            XCTAssertTrue(XcodeReporter().report(result, verbosity: verbosity).hasPrefix("/repo/a.swift:3:1: error:"))
        }
    }
}
