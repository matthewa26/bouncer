import XCTest
import Foundation
import BouncerCore
@testable import BouncerHeuristicAnalyzer

final class HeuristicAnalyzerTests: XCTestCase {
    func testFlagsABareExceptInPython() throws {
        let file = SourceFile(
            path: URL(fileURLWithPath: "/repo/a.py"), language: .python,
            contents: "def f():\n    try:\n        pass\n    except:\n        pass\n"
        )
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [:])
        let findings = try HeuristicAnalyzer(language: .python).analyze(file: file, context: context)
        XCTAssertTrue(findings.contains { $0.ruleID == "python-bare-except" })
    }

    func testGivesUnrecognizedLanguagesABestEffortPass() throws {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.zig"), language: .other("zig"), contents: "fn main() void {}\n")
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [:])
        let findings = try HeuristicAnalyzer(language: .other("zig")).analyze(file: file, context: context)
        XCTAssertNotNil(findings)
    }

    func testRespectsADisabledRule() throws {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.py"), language: .python, contents: "except:\n    pass\n")
        let disabled = RuleSettings(enabled: false, severity: .warning, parameters: .empty)
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: ["python-bare-except": disabled])
        let findings = try HeuristicAnalyzer(language: .python).analyze(file: file, context: context)
        XCTAssertFalse(findings.contains { $0.ruleID == "python-bare-except" })
    }
}
