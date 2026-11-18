import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

final class HeuristicRulesTests: XCTestCase {
    private func file(_ contents: String, path: String = "/repo/a.py") -> SourceFile {
        SourceFile(path: URL(fileURLWithPath: path), language: .python, contents: contents)
    }

    private func context(ruleID: String, params: [String: RuleParameterValue] = [:]) -> AnalysisContext {
        let settings = RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: params))
        return AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [ruleID: settings])
    }

    func testTrailingWhitespaceFlagsALineEndingInASpaceOrTab() {
        let findings = TrailingWhitespaceRule().evaluate(
            file: file("clean\ntrailing space \nclean again\n"), context: context(ruleID: TrailingWhitespaceRule.ruleID)
        )
        XCTAssertEqual(findings.map(\.line), [2])
    }

    func testTrailingWhitespaceDoesNotFlagACleanFile() {
        let findings = TrailingWhitespaceRule().evaluate(
            file: file("clean\nalso clean\n"), context: context(ruleID: TrailingWhitespaceRule.ruleID)
        )
        XCTAssertTrue(findings.isEmpty)
    }

    func testTodoDensityFlagsAFileOverTheMarkerRatio() {
        let contents = "# TODO one\n# TODO two\nline\nline\n"
        let findings = TodoDensityRule().evaluate(
            file: file(contents), context: context(ruleID: TodoDensityRule.ruleID, params: ["maxPerHundredLines": .int(10)])
        )
        XCTAssertEqual(findings.count, 1)
    }

    func testTodoDensityDoesNotFlagAFileUnderTheMarkerRatio() {
        let contents = "# TODO one\n" + (1...20).map { "line \($0)" }.joined(separator: "\n")
        let findings = TodoDensityRule().evaluate(
            file: file(contents), context: context(ruleID: TodoDensityRule.ruleID, params: ["maxPerHundredLines": .int(10)])
        )
        XCTAssertTrue(findings.isEmpty)
    }

    func testDuplicateBlockFlagsARepeatedWindowOfLines() {
        let block = "a\nb\nc\nd\n"
        let findings = DuplicateBlockRule().evaluate(
            file: file(block + block), context: context(ruleID: DuplicateBlockRule.ruleID, params: ["windowSize": .int(4)])
        )
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.line, 5)
    }

    func testDuplicateBlockDoesNotFlagDistinctContent() {
        let findings = DuplicateBlockRule().evaluate(
            file: file("a\nb\nc\nd\ne\nf\ng\nh\n"),
            context: context(ruleID: DuplicateBlockRule.ruleID, params: ["windowSize": .int(4)])
        )
        XCTAssertTrue(findings.isEmpty)
    }

    func testSecretPatternFlagsAnAwsAccessKey() {
        let findings = SecretPatternRule().evaluate(
            file: file("key = \"AKIAABCDEFGHIJKLMNOP\"\n"), context: context(ruleID: SecretPatternRule.ruleID)
        )
        XCTAssertEqual(findings.count, 1)
    }

    func testSecretPatternFlagsAnInlinePassword() {
        let findings = SecretPatternRule().evaluate(
            file: file("password: \"hunter2hunter2\"\n"), context: context(ruleID: SecretPatternRule.ruleID)
        )
        XCTAssertEqual(findings.count, 1)
    }

    func testSecretPatternDoesNotFlagOrdinaryCode() {
        let findings = SecretPatternRule().evaluate(
            file: file("def f():\n    return 1\n"), context: context(ruleID: SecretPatternRule.ruleID)
        )
        XCTAssertTrue(findings.isEmpty)
    }

    func testDeepNestingFlagsALineIndentedPastTheLimit() {
        let contents = "if a:\n    if b:\n        if c:\n            deep()\n"
        let findings = DeepNestingRule().evaluate(
            file: file(contents), context: context(ruleID: DeepNestingRule.ruleID, params: ["maxDepth": .int(2), "indentWidth": .int(4)])
        )
        XCTAssertEqual(findings.map(\.line), [4])
    }

    func testDeepNestingDoesNotFlagShallowCode() {
        let contents = "if a:\n    shallow()\n"
        let findings = DeepNestingRule().evaluate(
            file: file(contents), context: context(ruleID: DeepNestingRule.ruleID, params: ["maxDepth": .int(2), "indentWidth": .int(4)])
        )
        XCTAssertTrue(findings.isEmpty)
    }

    func testHighCouplingFlagsAFileOverTheImportThreshold() {
        let profile = LanguageProfile(lineCommentPrefixes: ["#"], importLinePattern: "^import\\s")
        let contents = (1...5).map { "import mod\($0)" }.joined(separator: "\n")
        let findings = HighCouplingRule(profile: profile).evaluate(
            file: file(contents), context: context(ruleID: HighCouplingRule.ruleID, params: ["maxImports": .int(3)])
        )
        XCTAssertEqual(findings.count, 1)
    }

    func testHighCouplingDoesNotFlagAFileUnderTheImportThreshold() {
        let profile = LanguageProfile(lineCommentPrefixes: ["#"], importLinePattern: "^import\\s")
        let findings = HighCouplingRule(profile: profile).evaluate(
            file: file("import mod1\nimport mod2\n"),
            context: context(ruleID: HighCouplingRule.ruleID, params: ["maxImports": .int(3)])
        )
        XCTAssertTrue(findings.isEmpty)
    }

    func testCyclomaticComplexityFlagsAFunctionOverTheBranchLimit() {
        let profile = LanguageProfile(lineCommentPrefixes: ["#"], functionStartPattern: "^def\\s")
        let contents = "def f():\n    if a:\n        pass\n    if b:\n        pass\n    if c:\n        pass\n"
        let findings = CyclomaticComplexityRule(profile: profile).evaluate(
            file: file(contents), context: context(ruleID: CyclomaticComplexityRule.ruleID, params: ["max": .int(2)])
        )
        XCTAssertEqual(findings.count, 1)
    }

    func testCyclomaticComplexityDoesNotFlagASimpleFunction() {
        let profile = LanguageProfile(lineCommentPrefixes: ["#"], functionStartPattern: "^def\\s")
        let findings = CyclomaticComplexityRule(profile: profile).evaluate(
            file: file("def f():\n    return 1\n"),
            context: context(ruleID: CyclomaticComplexityRule.ruleID, params: ["max": .int(2)])
        )
        XCTAssertTrue(findings.isEmpty)
    }

    func testSwitchOnTypeSmellFlagsASwitchOverTheBranchThreshold() {
        let profile = LanguageProfile(
            lineCommentPrefixes: ["#"], switchStartPattern: "^switch\\s", switchBranchPattern: "^    case\\s"
        )
        let contents = "switch x:\n    case 1:\n    case 2:\n    case 3:\n    case 4:\n"
        let findings = SwitchOnTypeSmellRule(profile: profile).evaluate(
            file: file(contents), context: context(ruleID: SwitchOnTypeSmellRule.ruleID, params: ["maxBranches": .int(2)])
        )
        XCTAssertEqual(findings.count, 1)
    }

    func testSwitchOnTypeSmellDoesNotFlagASmallSwitch() {
        let profile = LanguageProfile(
            lineCommentPrefixes: ["#"], switchStartPattern: "^switch\\s", switchBranchPattern: "^    case\\s"
        )
        let contents = "switch x:\n    case 1:\n    case 2:\n"
        let findings = SwitchOnTypeSmellRule(profile: profile).evaluate(
            file: file(contents), context: context(ruleID: SwitchOnTypeSmellRule.ruleID, params: ["maxBranches": .int(2)])
        )
        XCTAssertTrue(findings.isEmpty)
    }
}
