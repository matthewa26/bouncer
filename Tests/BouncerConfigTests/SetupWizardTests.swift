import XCTest
import Foundation
@testable import BouncerConfig

final class SetupWizardTests: XCTestCase {
    private var scratchDir: URL!
    private var home: URL { scratchDir.appendingPathComponent("home") }
    private var repo: URL { scratchDir.appendingPathComponent("repo") }
    private var repoConfig: URL { repo.appendingPathComponent(".bouncer") }
    private var globalConfig: URL { home.appendingPathComponent(".bouncer") }

    override func setUpWithError() throws {
        scratchDir = FileManager.default.temporaryDirectory.appendingPathComponent("bouncer-wizard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratchDir)
    }

    /// One scripted answer per wizard question, in the order the wizard asks them.
    private func answers(
        start: String = "", verbosity: String = "", coverage: [String] = [""],
        thresholds: [String] = Array(repeating: "", count: SetupThreshold.all.count),
        magic: String = "", docs: String = "", refresh: String = "", workOrder: String = "",
        target: [String] = [""], confirm: [String] = [""]
    ) -> [String] {
        [start, verbosity] + coverage + thresholds + [magic, docs, refresh, workOrder] + target + confirm
    }

    /// Runs the wizard over scripted answers, in a repo of `fileCount` files (large by default, so the
    /// refresh question's default writes nothing).
    private func run(
        _ lines: [String], target: SetupTarget? = nil, fileCount: Int = 10_000
    ) throws -> (written: [URL], transcript: String) {
        let terminal = ScriptedTerminal(lines)
        let paths = SetupPaths(
            repoConfig: repoConfig, globalConfig: globalConfig, store: ProfileStore(repoRoot: repo, homeDirectory: home)
        )
        let wizard = SetupWizard(prompt: terminal.prompt, paths: paths, countFiles: { fileCount })
        let written = try wizard.run(target: target)
        XCTAssertTrue(terminal.lines.isEmpty, "Unconsumed answers: \(terminal.lines)\n\(terminal.output)")
        return (written, terminal.output)
    }

    private func json(at path: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
    }

    func testWritesOnlyChangedKeysAndKeepsUnrelatedOnes() throws {
        try #"{"exclude": ["vendor/**"], "rules": {"long-lines": {"enabled": false}}}"#
            .write(to: repoConfig, atomically: true, encoding: .utf8)
        var thresholds = Array(repeating: "", count: SetupThreshold.all.count)
        thresholds[0] = "25"
        let result = try run(answers(thresholds: thresholds, magic: "n"))
        XCTAssertEqual(result.written, [repoConfig])
        let written = try json(at: repoConfig)
        XCTAssertEqual(written["exclude"] as? [String], ["vendor/**"])
        let rules = try XCTUnwrap(written["rules"] as? [String: [String: Any]])
        XCTAssertEqual(rules["long-lines"]?["enabled"] as? Bool, false)
        XCTAssertEqual((rules["long-function"]?["params"] as? [String: Int])?["maxLines"], 25)
        XCTAssertEqual(rules["magic-number"]?["enabled"] as? Bool, false)
        XCTAssertEqual(Set(written.keys), ["exclude", "rules"])
        XCTAssertTrue(result.transcript.contains("rules.long-function.params.maxLines = 25"))
    }

    func testCoverageAndVerbosityAndDocumentationScope() throws {
        let lines = answers(verbosity: "quiet", coverage: ["y", "85", "build/lcov.info"], docs: "all")
        _ = try run(lines)
        let written = try json(at: repoConfig)
        XCTAssertEqual((written["output"] as? [String: String])?["verbosity"], "quiet")
        let coverage = try XCTUnwrap(written["coverage"] as? [String: Any])
        XCTAssertEqual(coverage["enabled"] as? Bool, true)
        XCTAssertEqual(coverage["threshold"] as? Double, 85)
        XCTAssertEqual(coverage["reportPath"] as? String, "build/lcov.info")
        let docs = try XCTUnwrap((written["rules"] as? [String: [String: Any]])?["missing-documentation"])
        XCTAssertEqual((docs["params"] as? [String: String])?["scope"], "all")
    }

    func testAllDefaultsFromBuiltInDefaultsWritesNothing() throws {
        let result = try run(answers(confirm: []))
        XCTAssertEqual(result.written, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoConfig.path))
        XCTAssertTrue(result.transcript.contains("nothing written"))
    }

    func testStartingFromKirbyShowsItsValuesAndSelectsItInBouncer() throws {
        let result = try run(answers(start: "kirby (bundled profile)"))
        XCTAssertTrue(result.transcript.contains("(long-function.maxLines) (1-1000) [10]"))
        XCTAssertEqual(try json(at: repoConfig) as NSDictionary, ["profile": "kirby"] as NSDictionary)
        let loaded = try ConfigLoader().load(globalPath: globalConfig, repoRoot: repo, profileName: nil)
        XCTAssertEqual(loaded.resolvedRuleSettings()["long-function"]?.parameters.int("maxLines", default: 0), 10)
    }

    func testCurrentDefaultProfileIsTheDefaultStartingPoint() throws {
        try #"{"profile": "kirby"}"#.write(to: globalConfig, atomically: true, encoding: .utf8)
        let result = try run(answers(target: ["2"]))
        XCTAssertTrue(result.transcript.contains("Choose [kirby (bundled profile)]"))
        XCTAssertEqual(result.written, [globalConfig])
    }

    func testSavingAGlobalProfileFromKirbyCopiesItAndCanSetTheDefault() throws {
        var thresholds = Array(repeating: "", count: SetupThreshold.all.count)
        thresholds[1] = "100"
        let lines = answers(start: "2", thresholds: thresholds, target: ["4", "team", "3"])
        let result = try run(lines)
        let profilePath = home.appendingPathComponent(".bouncer-profiles/team.json")
        XCTAssertEqual(result.written, [profilePath, globalConfig])
        let profile = try ProfileStore.read(profilePath)
        XCTAssertEqual(profile.rules?["long-function"]?.params?["maxLines"], .int(10))
        XCTAssertEqual(profile.rules?["long-lines"]?.params?["maxLength"], .int(100))
        XCTAssertEqual(try ConfigLoader().read(globalConfig).profile, "team")
        let loaded = try ConfigLoader().load(globalPath: globalConfig, repoRoot: repo, profileName: nil)
        XCTAssertEqual(loaded.resolvedRuleSettings()["long-lines"]?.parameters.int("maxLength", default: 0), 100)
    }

    func testFixedProfileTargetSkipsTheTargetQuestionAndRejectsBadNamesUpFront() throws {
        let result = try run(answers(target: ["1"]), target: .profile(name: "strict", scope: .repo))
        XCTAssertEqual(result.written, [repo.appendingPathComponent(".bouncer-profiles/strict.json")])
        XCTAssertTrue(result.transcript.contains("(an empty profile)"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoConfig.path))
    }

    func testInvalidProfileNameIsAskedAgain() throws {
        let result = try run(answers(target: ["3", "../evil", "ok", ""]))
        XCTAssertTrue(result.transcript.contains("Invalid profile name \"../evil\""))
        XCTAssertEqual(result.written, [repo.appendingPathComponent(".bouncer-profiles/ok.json")])
    }

    func testDecliningTheConfirmationWritesNothing() throws {
        let result = try run(answers(magic: "n", confirm: ["n"]))
        XCTAssertEqual(result.written, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoConfig.path))
    }

    func testEndOfInputAbortsWithoutWriting() throws {
        let paths = SetupPaths(
            repoConfig: repoConfig, globalConfig: globalConfig, store: ProfileStore(repoRoot: repo, homeDirectory: home)
        )
        let wizard = SetupWizard(prompt: ScriptedTerminal(["", "", "", "25"]).prompt, paths: paths, countFiles: { 0 })
        XCTAssertThrowsError(try wizard.run()) { XCTAssertEqual($0 as? PromptError, .endOfInput) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoConfig.path))
    }

    func testThresholdsTargetTheRealRuleIDsAndDefaults() {
        let keys = SetupThreshold.all.map { "\($0.ruleID).\($0.parameter)=\($0.defaultValue)" }
        XCTAssertEqual(keys, [
            "long-function.maxLines=40", "long-lines.maxLength=120", "file-length.maxLines=500",
            "cyclomatic-complexity.max=10", "cognitive-complexity.max=15", "long-parameter-list.maxParameters=5",
            "nesting-depth.maxDepth=4"
        ])
    }

    func testLargeRepoRecommendsNextScanAndItsDefaultWritesNothing() throws {
        let result = try run(answers(confirm: []), fileCount: SetupQuestions.immediateRefreshFileCutoff)
        XCTAssertTrue(result.transcript.contains("""
            When files change while an agent is working, when should Bouncer notice?
              1. On the next scan (recommended for large repos)
                 Results stay as they were until the agent scans again or verifies the files it edited.
              2. Immediately
                 Before every answer, Bouncer re-checks any file that changed. Always current, but slower on large repos.
            Choose [1]:\u{20}
            """), result.transcript)
        XCTAssertEqual(result.written, [])
    }

    func testSmallRepoRecommendsImmediateAndItsDefaultWritesIt() throws {
        let result = try run(answers(), fileCount: SetupQuestions.immediateRefreshFileCutoff - 1)
        XCTAssertTrue(result.transcript.contains("  1. On the next scan\n"), result.transcript)
        XCTAssertTrue(result.transcript.contains("  2. Immediately (recommended for this repo's size)\n"))
        XCTAssertTrue(result.transcript.contains("Choose [2]: "))
        XCTAssertTrue(result.transcript.contains(#"agent.refresh = "immediate""#), result.transcript)
        XCTAssertEqual((try json(at: repoConfig)["agent"] as? [String: String])?["refresh"], "immediate")
        let loaded = try ConfigLoader().load(globalPath: globalConfig, repoRoot: repo, profileName: nil)
        XCTAssertEqual(loaded.agent?.refresh, .immediate)
    }

    func testPickingImmediateInALargeRepoWritesIt() throws {
        _ = try run(answers(refresh: "2"))
        XCTAssertEqual(try json(at: repoConfig) as NSDictionary, ["agent": ["refresh": "immediate"]] as NSDictionary)
    }

    func testPickingNextScanInASmallRepoMatchesTheDefaultAndWritesNothing() throws {
        let result = try run(answers(refresh: "1", confirm: []), fileCount: 3)
        XCTAssertEqual(result.written, [])
    }

    func testRefreshAnswerIsComparedWithTheStartingPoint() throws {
        var base = BouncerConfig.empty
        base.agent = AgentConfig(refresh: .immediate)
        let questionCount = answers().count - 3
        let kept = ScriptedTerminal(Array(repeating: "", count: questionCount))
        let unchanged = try SetupQuestions(prompt: kept.prompt, base: base, countFiles: { 10_000 }).ask()
        XCTAssertNil(unchanged.agent, "The starting point's setting is the default, even against the recommendation")
        var lines = Array(repeating: "", count: questionCount)
        lines[lines.count - 2] = "1"
        let switched = try SetupQuestions(prompt: ScriptedTerminal(lines).prompt, base: base, countFiles: { 3 }).ask()
        XCTAssertEqual(switched.agent, AgentConfig(refresh: .nextScan))
    }

    func testWorkOrderQuestionFollowsRefreshAndDefaultsToQuickFixes() throws {
        let result = try run(answers(confirm: []))
        XCTAssertTrue(result.transcript.contains("""
            Choose [1]: When an agent asks Bouncer what to fix next, what should come first?
              1. Quick fixes first (recommended)
                 Small, local fixes, like a force unwrap or a missing doc comment, before anything that needs
                 restructuring, like a long function or duplicated code. The agent clears the most findings fastest.
              2. Most severe first
                 Errors before warnings, even when an error needs a refactor. Slower, but the riskiest problems go first.
            Choose [1]:\u{20}
            """), result.transcript)
        XCTAssertEqual(result.written, [])
    }

    func testPickingMostSevereFirstWritesIt() throws {
        let result = try run(answers(workOrder: "2"))
        XCTAssertTrue(result.transcript.contains(#"agent.workOrder = "severity-first""#), result.transcript)
        let expected: NSDictionary = ["agent": ["workOrder": "severity-first"]]
        XCTAssertEqual(try json(at: repoConfig) as NSDictionary, expected)
        let loaded = try ConfigLoader().load(globalPath: globalConfig, repoRoot: repo, profileName: nil)
        XCTAssertEqual(loaded.agent, AgentConfig(workOrder: .severityFirst))
    }

    func testWorkOrderAnswerIsComparedWithTheStartingPoint() throws {
        var base = BouncerConfig.empty
        base.agent = AgentConfig(workOrder: .severityFirst)
        let questionCount = answers().count - 3
        let kept = ScriptedTerminal(Array(repeating: "", count: questionCount))
        let unchanged = try SetupQuestions(prompt: kept.prompt, base: base, countFiles: { 10_000 }).ask()
        XCTAssertNil(unchanged.agent, "A blank answer keeps the starting point's order")
        XCTAssertTrue(kept.output.contains("Choose [2]: "), kept.output)
        var lines = Array(repeating: "", count: questionCount)
        lines[lines.count - 1] = "1"
        let terminal = ScriptedTerminal(lines)
        let switched = try SetupQuestions(prompt: terminal.prompt, base: base, countFiles: { 10_000 }).ask()
        XCTAssertEqual(switched.agent, AgentConfig(workOrder: .quickFixesFirst))
    }

    func testFileCountHonorsExcludesAndSkipsHiddenFiles() throws {
        for name in ["a.swift", "b.py", "vendor/c.js"] {
            let file = repo.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "x\n".write(to: file, atomically: true, encoding: .utf8)
        }
        try #"{"exclude": ["vendor/**"]}"#.write(to: repoConfig, atomically: true, encoding: .utf8)
        let paths = SetupPaths(
            repoConfig: repoConfig, globalConfig: globalConfig, store: ProfileStore(repoRoot: repo, homeDirectory: home)
        )
        XCTAssertEqual(RepoFileCount.analyzableFiles(paths: paths), 2)
    }
}
