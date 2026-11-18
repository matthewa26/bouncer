import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

final class LongFunctionRuleTests: XCTestCase {
    private let profile = LanguageProfile(lineCommentPrefixes: ["#"], functionStartPattern: #"^\s*def\s+\w+\s*\("#)

    private func context(maxLines: Int) -> AnalysisContext {
        let settings = RuleSettings(enabled: true, severity: .error, parameters: RuleParameters(values: ["maxLines": .int(maxLines)]))
        return AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [LongFunctionRule.ruleID: settings])
    }

    func testFlagsAFunctionOverTheLimit() {
        let body = (1...5).map { "    line\($0) = 1" }.joined(separator: "\n")
        let contents = "def big():\n\(body)\n"
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.py"), language: .python, contents: contents)
        let findings = LongFunctionRule(profile: profile).evaluate(file: file, context: context(maxLines: 3))
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.line, 1)
    }

    func testDoesNotFlagAFunctionWithinTheLimit() {
        let contents = "def small():\n    return 1\n"
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.py"), language: .python, contents: contents)
        let findings = LongFunctionRule(profile: profile).evaluate(file: file, context: context(maxLines: 10))
        XCTAssertTrue(findings.isEmpty)
    }

    func testProducesNoFindingsWithoutAFunctionStartPattern() {
        let noPatternProfile = LanguageProfile(lineCommentPrefixes: ["#"])
        let contents = "def big():\n    a = 1\n    b = 2\n    c = 3\n"
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.sql"), language: .sql, contents: contents)
        let findings = LongFunctionRule(profile: noPatternProfile).evaluate(file: file, context: context(maxLines: 1))
        XCTAssertTrue(findings.isEmpty)
    }
}
