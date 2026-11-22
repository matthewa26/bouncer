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
            "long-function is 67% of findings; disable it or baseline it to focus on the rest.",
            "Finished in 41.2s."
        ])
    }

    func testDominantRuleHintNeedsMoreThanHalfOfTheFindings() {
        let half = AnalysisResult(findings: [
            finding("duplicate-block", "A.swift"), finding("duplicate-block", "B.swift"),
            finding("magic-number", "A.swift"), finding("long-lines", "A.swift")
        ], coverage: nil)
        XCTAssertNil(ReportSummary.dominantRuleHint(half))
        let most = AnalysisResult(findings: half.findings + [finding("duplicate-block", "C.swift")], coverage: nil)
        XCTAssertEqual(
            ReportSummary.dominantRuleHint(most),
            "duplicate-block is 60% of findings; disable it or baseline it to focus on the rest."
        )
    }

    func testDominantRuleHintRoundsThePercentAndSkipsASingleRuleRun() {
        let findings = (0..<7).map { finding("duplicate-block", "\($0).swift") }
            + (0..<5).map { finding("magic-number", "\($0).swift") }
        let hint = ReportSummary.dominantRuleHint(AnalysisResult(findings: findings, coverage: nil))
        XCTAssertEqual(hint?.hasPrefix("duplicate-block is 58% of findings"), true)
        let single = AnalysisResult(findings: [finding("r", "A.swift"), finding("r", "B.swift")], coverage: nil)
        XCTAssertNil(ReportSummary.dominantRuleHint(single))
    }

    func testLinesForACleanRunAreTheOneLineSummary() {
        let result = AnalysisResult(findings: [], coverage: nil)
        XCTAssertEqual(ReportSummary.lines(result, repoRoot: root), ["No findings."])
        XCTAssertEqual(ReportSummary.line(result), "No findings.")
    }
}
