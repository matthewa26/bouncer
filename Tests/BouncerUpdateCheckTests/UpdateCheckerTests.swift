import XCTest
import Foundation
@testable import BouncerUpdateCheck

private struct FakeLookup: GitHubReleaseLookup {
    let result: Result<GitHubReleaseInfo, Error>
    func latestRelease(repo: String) async throws -> GitHubReleaseInfo { try result.get() }
}

private struct LookupFailure: Error {}

final class UpdateCheckerTests: XCTestCase {
    private var scratchDir: URL!

    override func setUpWithError() throws {
        scratchDir = FileManager.default.temporaryDirectory.appendingPathComponent("update-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratchDir)
    }

    private func cachePath() -> URL {
        scratchDir.appendingPathComponent("cache.json")
    }

    func testReportsAnUpdateWhenTheLatestShaDiffersFromTheCurrentOne() async {
        let checker = UpdateChecker(
            lookup: FakeLookup(result: .success(GitHubReleaseInfo(tagName: "v2.0.0", commitSHA: "new-sha"))),
            cachePath: cachePath(), currentSHA: "old-sha", repo: "owner/repo"
        )
        let result = await checker.check()
        XCTAssertTrue(result.updateAvailable)
        XCTAssertEqual(result.latestTag, "v2.0.0")
    }

    func testReportsNoUpdateWhenTheLatestShaMatchesTheCurrentOne() async {
        let checker = UpdateChecker(
            lookup: FakeLookup(result: .success(GitHubReleaseInfo(tagName: "v1.0.0", commitSHA: "same-sha"))),
            cachePath: cachePath(), currentSHA: "same-sha", repo: "owner/repo"
        )
        let result = await checker.check()
        XCTAssertFalse(result.updateAvailable)
    }

    func testANetworkFailureWithNoCacheReportsNoUpdate() async {
        let checker = UpdateChecker(
            lookup: FakeLookup(result: .failure(LookupFailure())), cachePath: cachePath(), currentSHA: "old-sha", repo: "owner/repo"
        )
        let result = await checker.check()
        XCTAssertFalse(result.updateAvailable)
        XCTAssertNil(result.latestTag)
    }

    func testAFreshCacheIsUsedWithoutCallingTheLookupAgain() async {
        let path = cachePath()
        let firstChecker = UpdateChecker(
            lookup: FakeLookup(result: .success(GitHubReleaseInfo(tagName: "v2.0.0", commitSHA: "new-sha"))),
            cachePath: path, currentSHA: "old-sha", repo: "owner/repo"
        )
        _ = await firstChecker.check()

        let counter = Counter()
        let secondChecker = UpdateChecker(lookup: CountingLookup(counter: counter), cachePath: path, currentSHA: "old-sha", repo: "owner/repo")
        let result = await secondChecker.check()

        XCTAssertEqual(counter.value, 0)
        XCTAssertTrue(result.updateAvailable)
        XCTAssertEqual(result.latestTag, "v2.0.0")
    }

    func testAStaleCacheTriggersAFreshLookup() async {
        let path = cachePath()
        let past: @Sendable () -> Date = { Date(timeIntervalSince1970: 0) }
        let firstChecker = UpdateChecker(
            lookup: FakeLookup(result: .success(GitHubReleaseInfo(tagName: "v2.0.0", commitSHA: "new-sha"))),
            cachePath: path, currentSHA: "old-sha", repo: "owner/repo", intervalHours: 24, now: past
        )
        _ = await firstChecker.check()

        let secondChecker = UpdateChecker(
            lookup: FakeLookup(result: .success(GitHubReleaseInfo(tagName: "v3.0.0", commitSHA: "newer-sha"))),
            cachePath: path, currentSHA: "old-sha", repo: "owner/repo", intervalHours: 24
        )
        let result = await secondChecker.check()
        XCTAssertEqual(result.latestTag, "v3.0.0")
    }
}

private final class Counter: @unchecked Sendable {
    private(set) var value = 0
    func increment() { value += 1 }
}

private struct CountingLookup: GitHubReleaseLookup {
    let counter: Counter
    func latestRelease(repo: String) async throws -> GitHubReleaseInfo {
        counter.increment()
        throw LookupFailure()
    }
}
