import XCTest
import Foundation
import BouncerCore
@testable import BouncerConfig

final class JobsConfigTests: XCTestCase {
    private var scratchDir: URL!

    override func setUpWithError() throws {
        scratchDir = FileManager.default.temporaryDirectory.appendingPathComponent("bouncer-jobs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratchDir)
    }

    private func decode(_ json: String) throws -> BouncerConfig {
        try JSONDecoder().decode(BouncerConfig.self, from: Data(json.utf8))
    }

    private func write(_ json: String, named name: String) throws -> URL {
        let path = scratchDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: path, atomically: true, encoding: .utf8)
        return path
    }

    func testJobsDecodesAndTheRepoLayerWins() throws {
        let global = try decode(#"{"jobs": 2}"#), repo = try decode(#"{"jobs": 6}"#)
        XCTAssertEqual(global.jobs, 2)
        XCTAssertEqual(global.merging(repo).jobs, 6)
        XCTAssertEqual(global.merging(.empty).jobs, 2)
        XCTAssertNil(BouncerConfig.empty.merging(.empty).jobs)
    }

    func testTheFlagBeatsConfigWhichBeatsTheCoreCount() throws {
        let config = try decode(#"{"jobs": 3}"#)
        XCTAssertEqual(config.jobs(overriddenBy: 5), 5)
        XCTAssertEqual(config.jobs(overriddenBy: nil), 3)
        XCTAssertEqual(BouncerConfig.empty.jobs(overriddenBy: nil), AnalysisEngine.defaultJobs)
    }

    func testJobsBelowOneIsAConfigError() throws {
        let repoDir = scratchDir.appendingPathComponent("repo")
        _ = try write(#"{"jobs": 0}"#, named: "repo/.bouncer")
        let global = scratchDir.appendingPathComponent("missing-global.json")
        XCTAssertThrowsError(try ConfigLoader().load(globalPath: global, repoRoot: repoDir, profileName: nil)) {
            let error = $0 as? ConfigError
            XCTAssertEqual(error, .invalidJobs(path: repoDir.appendingPathComponent(".bouncer").path, value: 0))
            XCTAssertTrue(error?.description.contains("at least 1") == true)
        }
    }

    func testFindingSettingsDropJobsAndAgentButKeepTheRest() throws {
        let config = try decode(#"{"jobs": 4, "agent": {"refresh": "immediate"}, "exclude": ["a/**"]}"#)
        let settings = config.findingSettings
        XCTAssertNil(settings.jobs)
        XCTAssertNil(settings.agent)
        XCTAssertEqual(settings.exclude, ["a/**"])
        XCTAssertEqual(settings, try decode(#"{"exclude": ["a/**"]}"#).findingSettings)
    }
}
