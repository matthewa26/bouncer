import XCTest
import BouncerCore
@testable import BouncerConfig

final class BouncerConfigMergeTests: XCTestCase {
    func testRepoLevelScalarOverridesGlobal() {
        let global = BouncerConfig(output: OutputConfig(verbosity: .quiet))
        let repo = BouncerConfig(output: OutputConfig(verbosity: .verbose))
        let merged = global.merging(repo)
        XCTAssertEqual(merged.output?.verbosity, .verbose)
    }

    func testGlobalValueSurvivesWhenRepoDoesNotOverrideIt() {
        let global = BouncerConfig(coverage: CoverageConfig(threshold: 90))
        let repo = BouncerConfig(coverage: CoverageConfig(enabled: true))
        let merged = global.merging(repo)
        XCTAssertEqual(merged.coverage?.threshold, 90)
        XCTAssertEqual(merged.coverage?.enabled, true)
    }

    func testHooksConcatenateRatherThanOverride() {
        let global = BouncerConfig(hooks: HooksConfig(preCheck: ["global-hook"]))
        let repo = BouncerConfig(hooks: HooksConfig(preCheck: ["repo-hook"]))
        let merged = global.merging(repo)
        XCTAssertEqual(merged.hooks?.preCheck, ["global-hook", "repo-hook"])
    }

    func testRuleEntriesMergeFieldByFieldRatherThanReplacingWholesale() {
        let global = BouncerConfig(rules: ["long-function": RuleConfigEntry(severity: .warning, params: ["maxLines": .int(50)])])
        let repo = BouncerConfig(rules: ["long-function": RuleConfigEntry(severity: .error)])
        let merged = global.merging(repo)
        let resolved = merged.resolvedRuleSettings()["long-function"]
        XCTAssertEqual(resolved?.severity, .error)
        XCTAssertEqual(resolved?.parameters.int("maxLines", default: 0), 50)
    }
}
