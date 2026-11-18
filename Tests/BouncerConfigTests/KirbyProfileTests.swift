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
