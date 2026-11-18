import XCTest
import Foundation
import BouncerCore
@testable import BouncerConfig

final class JSONBaselineStoreTests: XCTestCase {
    private func scratchPath() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("baseline-\(UUID().uuidString).json")
    }

    func testLoadingAMissingFileReturnsAnEmptyBaseline() throws {
        let baseline = try JSONBaselineStore().load(from: scratchPath())
        XCTAssertTrue(baseline.fingerprints.isEmpty)
    }

    func testWritingThenLoadingRoundTripsTheFingerprints() throws {
        let path = scratchPath()
        defer { try? FileManager.default.removeItem(at: path) }
        let fingerprint = Baseline.fingerprint(ruleID: "long-function", relativePath: "a.swift", lineContent: "func f() {")
        let store = JSONBaselineStore()
        try store.write(Baseline(fingerprints: [fingerprint]), to: path)
        let loaded = try store.load(from: path)
        XCTAssertTrue(loaded.contains(fingerprint))
    }
}
