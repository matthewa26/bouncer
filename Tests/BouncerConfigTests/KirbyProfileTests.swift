import XCTest
@testable import BouncerConfig

final class KirbyProfileTests: XCTestCase {
    func testSetsTheTenLineFunctionLimit() {
        let resolved = KirbyProfile.config.resolvedRuleSettings()["long-function"]
        XCTAssertEqual(resolved?.parameters.int("maxLines", default: 0), 10)
    }

    func testRequiresDocumentationAtAllScopes() {
        let resolved = KirbyProfile.config.resolvedRuleSettings()["missing-documentation"]
        XCTAssertEqual(resolved?.parameters.string("scope", default: ""), "all")
    }

    func testCapsParametersAndCognitiveComplexity() {
        let resolved = KirbyProfile.config.resolvedRuleSettings()
        XCTAssertEqual(resolved["long-parameter-list"]?.parameters.int("maxParameters", default: 0), 3)
        XCTAssertEqual(resolved["cognitive-complexity"]?.parameters.int("max", default: 0), 8)
    }

    func testTreatsEverySingleLocationSmellAsAnError() {
        let resolved = KirbyProfile.config.resolvedRuleSettings()
        for ruleID in ["force-unwrap", "explicit-any", "non-null-assertion", "empty-catch", "magic-number"] {
            XCTAssertEqual(resolved[ruleID]?.severity, .error, ruleID)
        }
    }

    func testProfileIsOverriddenByAHigherPrecedenceLayer() {
        let repoOverride = BundledProfiles.profile(named: "kirby").merging(
            BouncerConfig(rules: ["long-function": RuleConfigEntry(params: ["maxLines": .int(25)])])
        )
        XCTAssertEqual(repoOverride.resolvedRuleSettings()["long-function"]?.parameters.int("maxLines", default: 0), 25)
    }

    func testUnknownProfileNameResolvesToEmpty() {
        XCTAssertEqual(BundledProfiles.profile(named: "not-a-real-profile"), BouncerConfig.empty)
    }
}
