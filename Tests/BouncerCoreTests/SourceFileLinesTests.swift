import XCTest
import Foundation
import BouncerCore

final class SourceFileLinesTests: XCTestCase {
    func testSplitsLFAndCRLFAlikeOnEveryPlatform() {
        XCTAssertEqual(SourceFile.lines(of: "a\nb\nc"), ["a", "b", "c"])
        XCTAssertEqual(SourceFile.lines(of: "a\r\nb\r\nc"), ["a", "b", "c"])
        XCTAssertEqual(SourceFile.lines(of: "a\r\nb\nc\r\n"), ["a", "b", "c", ""])
        XCTAssertEqual(SourceFile.lines(of: ""), [""])
    }

    func testSourceFileLinesMatchTheSplitter() {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.ts"), language: .typescript, contents: "x\r\ny\n")
        XCTAssertEqual(file.lines, SourceFile.lines(of: file.contents))
    }

    func testLooksForAGeneratedMarkerOnlyInTheFirstTenCRLFLines() {
        let body = String(repeating: "x\r\n", count: 12)
        XCTAssertTrue(FactText.isGenerated("// @generated\r\n" + body))
        XCTAssertFalse(FactText.isGenerated(body + "// DO NOT EDIT\r\n"))
    }
}
