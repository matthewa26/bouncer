import XCTest
import BouncerCore
@testable import BouncerConfig

final class OWASPProfileTests: XCTestCase {
    func testEnablesEveryMappedSecurityRuleAsAnError() {
        let resolved = BundledProfiles.profile(named: "owasp").resolvedRuleSettings()
        for ruleID in OWASPCategory.mappedRuleIDs {
            XCTAssertEqual(resolved[ruleID]?.enabled, true, ruleID)
            XCTAssertEqual(resolved[ruleID]?.severity, .error, ruleID)
        }
        XCTAssertTrue(BundledProfiles.names.contains("owasp"))
    }

    func testLeavesRulesOutsideTheMappingAtTheirDefaults() {
        XCTAssertNil(OWASPProfile.config.rules?["long-function"])
        XCTAssertEqual(OWASPProfile.config.rules?.count, OWASPCategory.mappedRuleIDs.count)
    }

    func testIsOverriddenByAHigherPrecedenceLayer() {
        let repo = OWASPProfile.config.merging(
            BouncerConfig(rules: ["ssrf": RuleConfigEntry(severity: .warning)])
        )
        XCTAssertEqual(repo.resolvedRuleSettings()["ssrf"]?.severity, .warning)
    }
}
