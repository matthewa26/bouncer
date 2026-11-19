import XCTest
import Foundation
@testable import BouncerCore

final class SuppressionsTests: XCTestCase {
    private func suppressions(_ contents: String, language: Language = .swift) -> Suppressions {
        Suppressions(file: SourceFile(path: URL(fileURLWithPath: "/repo/a"), language: language, contents: contents))
    }

    func testDisableLineCoversOnlyItsOwnLine() {
        let s = suppressions("let a = 42 // bouncer:disable-line magic-number\nlet b = 43\n")
        XCTAssertTrue(s.suppresses("magic-number", at: 1))
        XCTAssertFalse(s.suppresses("magic-number", at: 2))
        XCTAssertFalse(s.suppresses("long-lines", at: 1))
    }

    func testDisableNextLineSkipsBlankLinesAndStackedDirectives() {
        let source = """
            // bouncer:disable-next-line parallel-inheritance -- one resolver per language is deliberate

            // bouncer:disable-next-line magic-number, long-lines
            protocol ImportResolver {}
            let other = 1
            """
        let s = suppressions(source)
        XCTAssertTrue(s.suppresses("parallel-inheritance", at: 4))
        XCTAssertTrue(s.suppresses("magic-number", at: 4))
        XCTAssertTrue(s.suppresses("long-lines", at: 4))
        XCTAssertFalse(s.suppresses("parallel-inheritance", at: 5))
    }

    func testDisableAndEnableBoundARangePerRule() {
        let source = """
            # bouncer:disable long-function, magic-number
            def a(): pass
            # bouncer:enable magic-number
            def b(): pass
            """
        let s = suppressions(source, language: .python)
        XCTAssertTrue(s.suppresses("magic-number", at: 2))
        XCTAssertFalse(s.suppresses("magic-number", at: 4))
        XCTAssertTrue(s.suppresses("long-function", at: 4), "only magic-number was re-enabled")
    }

    func testDisableFileCoversEveryLineInAnyCommentStyle() {
        for header in ["-- bouncer:disable-file sql-select-star", "/* bouncer:disable-file sql-select-star */",
                       "<!-- bouncer:disable-file sql-select-star -->"] {
            let s = suppressions(header + "\nSELECT * FROM t;\n", language: .sql)
            XCTAssertTrue(s.suppresses("sql-select-star", at: 2), header)
        }
    }

    func testIgnoresDirectivesOutsideCommentsAndWithoutRules() {
        let s = suppressions("let text = \"bouncer:disable-line magic-number\"; let x = 7\n// bouncer:disable-file\n")
        XCTAssertFalse(s.suppresses("magic-number", at: 1))
        XCTAssertFalse(s.suppresses("magic-number", at: 2))
    }
}
