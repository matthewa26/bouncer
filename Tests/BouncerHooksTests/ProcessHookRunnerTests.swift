import XCTest
import Foundation
@testable import BouncerHooks

final class ProcessHookRunnerTests: XCTestCase {
    private var scratchDir: URL!

    override func setUpWithError() throws {
        scratchDir = FileManager.default.temporaryDirectory.appendingPathComponent("hooks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratchDir)
    }

    func testRunsEveryCommandWhenAllSucceed() {
        let results = ProcessHookRunner(workingDirectory: scratchDir).run(["exit 0", "exit 0"])
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy(\.succeeded))
    }

    func testStopsAtTheFirstFailure() {
        let results = ProcessHookRunner(workingDirectory: scratchDir).run(["exit 0", "exit 1", "exit 0"])
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results[0].succeeded)
        XCTAssertFalse(results[1].succeeded)
    }

    func testRecordsTheExitCodeOfAFailingCommand() {
        let results = ProcessHookRunner(workingDirectory: scratchDir).run(["exit 7"])
        XCTAssertEqual(results.first?.exitCode, 7)
    }

    func testRunsInTheGivenWorkingDirectory() throws {
        let markerPath = scratchDir.appendingPathComponent("marker")
        _ = ProcessHookRunner(workingDirectory: scratchDir).run(["echo x > marker"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerPath.path))
    }

    func testAnEmptyCommandListProducesNoResults() {
        XCTAssertTrue(ProcessHookRunner(workingDirectory: scratchDir).run([]).isEmpty)
    }
}
