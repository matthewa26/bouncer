import XCTest
import Foundation
@testable import BouncerConfig

final class ConfigLoaderTests: XCTestCase {
    private var scratchDir: URL!

    override func setUpWithError() throws {
        scratchDir = FileManager.default.temporaryDirectory.appendingPathComponent("bouncer-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratchDir)
    }

    private func write(_ json: String, named name: String) throws -> URL {
        let path = scratchDir.appendingPathComponent(name)
        try json.write(to: path, atomically: true, encoding: .utf8)
        return path
    }

    func testMissingGlobalAndRepoFilesResolveToBundledDefaults() throws {
        let globalPath = scratchDir.appendingPathComponent("missing-global.json")
        let config = try ConfigLoader().load(globalPath: globalPath, repoRoot: nil, profileName: nil)
        XCTAssertNil(config.output)
    }

    func testRepoFileOverridesGlobalFile() throws {
        let globalPath = try write(#"{"output": {"verbosity": "quiet"}}"#, named: "global.json")
        let repoDir = scratchDir.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        _ = try write(#"{"output": {"verbosity": "verbose"}}"#, named: "repo/.bouncer")
        let config = try ConfigLoader().load(globalPath: globalPath, repoRoot: repoDir, profileName: nil)
        XCTAssertEqual(config.output?.verbosity, .verbose)
    }

    func testProfileAppliesBeneathGlobalAndRepoConfig() throws {
        let globalPath = scratchDir.appendingPathComponent("missing-global.json")
        let config = try ConfigLoader().load(globalPath: globalPath, repoRoot: nil, profileName: "kirby")
        XCTAssertEqual(config.resolvedRuleSettings()["long-function"]?.parameters.int("maxLines", default: 0), 10)
    }

    func testInvalidJsonThrows() throws {
        let globalPath = try write("not valid json", named: "bad-global.json")
        XCTAssertThrowsError(try ConfigLoader().load(globalPath: globalPath, repoRoot: nil, profileName: nil))
    }
}
