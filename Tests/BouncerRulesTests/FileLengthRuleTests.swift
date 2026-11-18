import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

final class FileLengthRuleTests: XCTestCase {
    private let profile = LanguageProfile(lineCommentPrefixes: ["#"])

    private func context(maxLines: Int) -> AnalysisContext {
        let settings = RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: ["maxLines": .int(maxLines)]))
        return AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [FileLengthRule.ruleID: settings])
    }

    func testFlagsAFileOverTheLimit() {
        let contents = (1...5).map { "line \($0)" }.joined(separator: "\n")
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.py"), language: .python, contents: contents)
        let findings = FileLengthRule(profile: profile).evaluate(file: file, context: context(maxLines: 3))
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.ruleID, FileLengthRule.ruleID)
    }

    func testDoesNotFlagAFileWithinTheLimit() {
        let contents = (1...3).map { "line \($0)" }.joined(separator: "\n")
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.py"), language: .python, contents: contents)
        let findings = FileLengthRule(profile: profile).evaluate(file: file, context: context(maxLines: 5))
        XCTAssertTrue(findings.isEmpty)
    }

    func testExcludesBlankAndCommentLinesFromTheCount() {
        let contents = "line 1\n\n# a comment\nline 2\n"
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.py"), language: .python, contents: contents)
        let findings = FileLengthRule(profile: profile).evaluate(file: file, context: context(maxLines: 2))
        XCTAssertTrue(findings.isEmpty)
    }
}
