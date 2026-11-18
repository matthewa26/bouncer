import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

final class NamingConventionRuleTests: XCTestCase {
    private let pythonProfile = LanguageProfile(
        lineCommentPrefixes: ["#"],
        namingRules: [NamingRule(declarationPattern: #"\bdef\s+([A-Za-z_]\w*)"#, expectedIdentifierPattern: #"^[a-z_][a-z0-9_]*$"#, kindLabel: "function")]
    )

    private let context = AnalysisContext(
        repoRoot: URL(fileURLWithPath: "/repo"),
        ruleSettings: [NamingConventionRule.ruleID: RuleSettings(enabled: true, severity: .warning, parameters: .empty)]
    )

    func testFlagsAFunctionNameThatDoesNotMatchTheConvention() {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.py"), language: .python, contents: "def BadName():\n    pass\n")
        let findings = NamingConventionRule(profile: pythonProfile).evaluate(file: file, context: context)
        XCTAssertEqual(findings.count, 1)
    }

    func testDoesNotFlagAConformingFunctionName() {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.py"), language: .python, contents: "def good_name():\n    pass\n")
        let findings = NamingConventionRule(profile: pythonProfile).evaluate(file: file, context: context)
        XCTAssertTrue(findings.isEmpty)
    }
}
