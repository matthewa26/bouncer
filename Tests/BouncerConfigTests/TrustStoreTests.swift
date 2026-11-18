import XCTest
import Foundation
@testable import BouncerConfig

final class TrustStoreTests: XCTestCase {
    private func scratchPath() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("trust-\(UUID().uuidString).json")
    }

    func testAnUntrustedRepoIsNotTrusted() {
        let store = TrustStore(path: scratchPath())
        XCTAssertFalse(store.isTrusted(repoPath: "/repo", hooksHash: "abc"))
    }

    func testTrustingARepoMakesItTrustedForThatExactHash() throws {
        let path = scratchPath()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = TrustStore(path: path)
        try store.trust(repoPath: "/repo", hooksHash: "abc")
        XCTAssertTrue(store.isTrusted(repoPath: "/repo", hooksHash: "abc"))
    }

    func testEditingTrustedHooksRevokesTrustForTheOldHash() throws {
        let path = scratchPath()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = TrustStore(path: path)
        try store.trust(repoPath: "/repo", hooksHash: "abc")
        XCTAssertFalse(store.isTrusted(repoPath: "/repo", hooksHash: "def"))
    }

    func testContentHashChangesWhenHooksChange() {
        let a = TrustStore.contentHash(of: HooksConfig(preCheck: ["echo one"]))
        let b = TrustStore.contentHash(of: HooksConfig(preCheck: ["echo two"]))
        XCTAssertNotEqual(a, b)
    }

    func testContentHashIsStableForIdenticalHooks() {
        let a = TrustStore.contentHash(of: HooksConfig(preCheck: ["echo one"], postCheck: ["echo done"]))
        let b = TrustStore.contentHash(of: HooksConfig(preCheck: ["echo one"], postCheck: ["echo done"]))
        XCTAssertEqual(a, b)
    }
}
