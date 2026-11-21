import XCTest
import BouncerCore
@testable import BouncerConfig

final class RuleDefaultSeverityTests: XCTestCase {
    func testUnpinnedCIActionDefaultsToInfoOnceEnabled() {
        let config = BouncerConfig(rules: ["unpinned-ci-action": RuleConfigEntry(enabled: true)])
        XCTAssertEqual(config.resolvedRuleSettings()["unpinned-ci-action"]?.severity, .info)
    }

    func testAConfiguredSeverityStillWinsAndOtherRulesDefaultToWarning() {
        let config = BouncerConfig(rules: [
            "unpinned-ci-action": RuleConfigEntry(severity: .error), "pipe-to-shell": RuleConfigEntry(enabled: true)
        ])
        XCTAssertEqual(config.resolvedRuleSettings()["unpinned-ci-action"]?.severity, .error)
        XCTAssertEqual(config.resolvedRuleSettings()["pipe-to-shell"]?.severity, .warning)
    }
}
