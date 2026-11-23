import XCTest
@testable import BouncerMCP

final class ResponseBudgetTests: XCTestCase {
    func testDefaultsToTwoThousandTokens() {
        XCTAssertEqual(ResponseBudget().maxChars, 8_000)
        XCTAssertEqual(ResponseBudget(arguments: [:]).maxChars, 8_000)
    }

    func testConvertsTokensToCharacters() {
        XCTAssertEqual(ResponseBudget(maxTokens: 100).maxChars, 400)
        XCTAssertEqual(ResponseBudget(maxChars: 123).maxChars, 123)
    }

    func testTheSmallerCapWins() {
        XCTAssertEqual(ResponseBudget(maxTokens: 100, maxChars: 1_000).maxChars, 400)
        XCTAssertEqual(ResponseBudget(maxTokens: 100, maxChars: 50).maxChars, 50)
    }

    func testReadsArguments() {
        XCTAssertEqual(ResponseBudget(arguments: ["max_tokens": 10]).maxChars, 40)
        XCTAssertEqual(ResponseBudget(arguments: ["max_chars": 30.0]).maxChars, 30)
        XCTAssertEqual(ResponseBudget(arguments: ["max_tokens": 10, "max_chars": 30]).maxChars, 30)
        XCTAssertEqual(ResponseBudget(arguments: ["max_tokens": "10"]).maxChars, 8_000)
    }

    func testNegativeAndHugeCapsAreClamped() {
        XCTAssertEqual(ResponseBudget(maxChars: -5).maxChars, 0)
        XCTAssertEqual(ResponseBudget(maxTokens: Int.max).maxChars, Int.max)
        XCTAssertEqual(ResponseBudget(maxTokens: Int.min).maxChars, 0)
    }

    func testLeavesTextThatFitsAlone() {
        let fitted = ResponseBudget(maxChars: 11).fit("hello\nworld")
        XCTAssertEqual(fitted.text, "hello\nworld")
        XCTAssertFalse(fitted.truncated)
    }

    func testCutsAtTheLastLineBoundaryThatFits() {
        let fitted = ResponseBudget(maxChars: 16).fit("one\ntwo\nthree\nfour")
        XCTAssertEqual(fitted.text, "one\ntwo\nthree")
        XCTAssertTrue(fitted.truncated)
    }

    func testKeepsALineThatEndsExactlyAtTheCap() {
        for cap in [7, 8] {
            let fitted = ResponseBudget(maxChars: cap).fit("one\ntwo\nthree")
            XCTAssertEqual(fitted.text, "one\ntwo", "cap \(cap)")
            XCTAssertTrue(fitted.truncated)
        }
    }

    func testReservingLeavesRoomForANote() {
        let budget = ResponseBudget(maxChars: 14)
        let fitted = budget.fit("one\ntwo\nthree\nfour", reserving: 6)
        XCTAssertEqual(fitted.text, "one\ntwo")
        XCTAssertTrue(fitted.truncated)
        XCTAssertLessThanOrEqual(fitted.text.count + 6, budget.maxChars)
    }

    func testCutsALongFirstLineMidLine() {
        let fitted = ResponseBudget(maxChars: 5).fit("abcdefghij\nk")
        XCTAssertEqual(fitted.text, "abcde")
        XCTAssertTrue(fitted.truncated)
    }

    func testNeverExceedsTheCap() {
        let text = (1...200).map { "line \($0) " + String(repeating: "x", count: $0 % 17) }.joined(separator: "\n")
        for cap in [0, 1, 7, 50, 333, 1_000] {
            for reserved in [0, 3, 40] {
                let fitted = ResponseBudget(maxChars: cap).fit(text, reserving: reserved)
                XCTAssertLessThanOrEqual(fitted.text.count, max(0, cap - reserved))
                XCTAssertTrue(fitted.truncated)
                XCTAssertTrue(text.hasPrefix(fitted.text))
            }
        }
    }
}
