import XCTest
import Foundation
@testable import BouncerCoverage

final class LCOVCoverageProviderTests: XCTestCase {
    func testComputesOverallLineCoveragePercent() throws {
        let lcov = "SF:a.swift\nLF:10\nLH:5\nend_of_record\nSF:b.swift\nLF:10\nLH:10\nend_of_record\n"
        let path = try write(lcov, named: "test.info")
        defer { try? FileManager.default.removeItem(at: path) }
        let report = try LCOVCoverageProvider().parse(reportPath: path)
        XCTAssertEqual(report.overallLineCoveragePercent, 75, accuracy: 0.001)
    }

    func testRecognizesInfoAndLcovExtensions() {
        let provider = LCOVCoverageProvider()
        XCTAssertTrue(provider.canParse(reportPath: URL(fileURLWithPath: "/tmp/x.info")))
        XCTAssertTrue(provider.canParse(reportPath: URL(fileURLWithPath: "/tmp/x.lcov")))
        XCTAssertFalse(provider.canParse(reportPath: URL(fileURLWithPath: "/tmp/x.xcresult")))
    }

    private func write(_ contents: String, named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
