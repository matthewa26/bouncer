import XCTest
import Foundation
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

    func testSaveRunDecodesAndSurvivesAMergeThatDoesNotSetIt() throws {
        let repo = try JSONDecoder().decode(BouncerConfig.self, from: Data(#"{"output": {"saveRun": false}}"#.utf8))
        XCTAssertEqual(repo.output?.saveRun, false)
        let merged = repo.merging(BouncerConfig(output: OutputConfig(verbosity: .quiet)))
        XCTAssertEqual(merged.output?.saveRun, false)
        XCTAssertEqual(merged.output?.verbosity, .quiet)
        XCTAssertNil(BouncerConfig.empty.output?.saveRun)
    }

    func testAgentRefreshDecodesAndSurvivesAMergeThatDoesNotSetIt() throws {
        let repo = try JSONDecoder().decode(BouncerConfig.self, from: Data(#"{"agent": {"refresh": "next-scan"}}"#.utf8))
        XCTAssertEqual(repo.agent?.refresh, .nextScan)
        XCTAssertEqual(repo.merging(BouncerConfig(profile: "kirby")).agent?.refresh, .nextScan)
        var global = BouncerConfig()
        global.agent = AgentConfig(refresh: .immediate)
        XCTAssertEqual(global.merging(repo).agent?.refresh, .nextScan)
    }

    func testAgentWorkOrderDecodesAndSurvivesAMergeThatOnlySetsRefresh() throws {
        let json = Data(#"{"agent": {"workOrder": "severity-first"}}"#.utf8)
        let repo = try JSONDecoder().decode(BouncerConfig.self, from: json)
        XCTAssertEqual(repo.agent?.workOrder, .severityFirst)
        var refreshOnly = BouncerConfig()
        refreshOnly.agent = AgentConfig(refresh: .immediate)
        XCTAssertEqual(repo.merging(refreshOnly).agent, AgentConfig(refresh: .immediate, workOrder: .severityFirst))
        XCTAssertEqual(refreshOnly.merging(repo).agent, AgentConfig(refresh: .immediate, workOrder: .severityFirst))
        XCTAssertNil(BouncerConfig.empty.agent?.workOrder)
    }
}
