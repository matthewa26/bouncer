import XCTest
import Foundation
import BouncerCore
import BouncerReporting

final class ReportSummaryLinesTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")

    private func finding(_ rule: String, _ path: String, _ severity: Severity = .warning) -> Finding {
        Finding(ruleID: rule, severity: severity, filePath: root.appendingPathComponent(path), line: 1, message: "m")
    }

    func testTopKeepsFiveMostFrequentBreakingTiesByName() {
        let names = ["f", "e", "e", "d", "d", "c", "c", "b", "b", "a", "a", "a", "g"]
        let top = ReportSummary.top(names)
        XCTAssertEqual(top.map(\.name), ["a", "b", "c", "d", "e"])
        XCTAssertEqual(top.map(\.count), [3, 2, 2, 2, 2])
    }

    func testLinesSummarizeSeverityRulesFilesAndTime() {
        let result = AnalysisResult(findings: [
            finding("long-function", "Sources/A.swift", .error),
            finding("long-function", "Sources/B.swift"),
            finding("magic-number", "Sources/A.swift", .info)
        ], coverage: nil)
        XCTAssertEqual(ReportSummary.lines(result, repoRoot: root, elapsed: .milliseconds(41_200)), [
            "3 findings: 1 error, 1 warning, 1 info.",
            "Top rules:",
            "  2  long-function",
            "  1  magic-number",
            "Top files:",
            "  2  Sources/A.swift",
            "  1  Sources/B.swift",
            "Finished in 41.2s."
        ])
    }

    func testLinesForACleanRunAreTheOneLineSummary() {
        let result = AnalysisResult(findings: [], coverage: nil)
        XCTAssertEqual(ReportSummary.lines(result, repoRoot: root), ["No findings."])
        XCTAssertEqual(ReportSummary.line(result), "No findings.")
    }
}
