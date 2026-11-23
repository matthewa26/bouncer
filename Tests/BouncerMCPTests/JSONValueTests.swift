import XCTest
@testable import BouncerMCP

final class JSONValueTests: XCTestCase {
    func testLiteralsBuildTheMatchingCases() {
        let value: JSONValue = ["s": "x", "i": 3, "d": 1.5, "b": true, "a": [1, "two"], "o": [:]]
        XCTAssertEqual(value["s"], .string("x"))
        XCTAssertEqual(value["i"], .number(3))
        XCTAssertEqual(value["d"], .number(1.5))
        XCTAssertEqual(value["b"], .bool(true))
        XCTAssertEqual(value["a"], .array([.number(1), .string("two")]))
        XCTAssertEqual(value["o"], .object([:]))
    }

    func testAccessorsReturnNilForOtherKinds() {
        let value: JSONValue = "text"
        XCTAssertEqual(value.stringValue, "text")
        XCTAssertNil(value.intValue)
        XCTAssertNil(value.boolValue)
        XCTAssertNil(value.arrayValue)
        XCTAssertNil(value.objectValue)
        XCTAssertNil(value["key"])
        XCTAssertEqual(JSONValue.bool(false).boolValue, false)
        XCTAssertEqual(JSONValue.array([1]).arrayValue, [1])
    }

    func testIntValueAcceptsOnlyWholeNumbers() throws {
        XCTAssertEqual(try JSONValue.parse("1").intValue, 1)
        XCTAssertEqual(try JSONValue.parse("1.0").intValue, 1)
        XCTAssertEqual(try JSONValue.parse("-20").intValue, -20)
        XCTAssertNil(try JSONValue.parse("1.5").intValue)
        XCTAssertNil(try JSONValue.parse("1e300").intValue)
    }

    func testParsesEveryKind() throws {
        let value = try JSONValue.parse(#"{"n":null,"b":false,"x":2.25,"s":"é\n","a":[true,{}]}"#)
        XCTAssertEqual(value, ["n": .null, "b": false, "x": 2.25, "s": "é\n", "a": [true, [:]]])
    }

    func testBooleansAndNumbersStayDistinct() throws {
        XCTAssertEqual(try JSONValue.parse("true"), .bool(true))
        XCTAssertEqual(try JSONValue.parse("1"), .number(1))
        XCTAssertEqual(try JSONValue.parse("0"), .number(0))
    }

    func testEncodesCompactlyOnOneLineWithIntegersWithoutFraction() throws {
        let value: JSONValue = ["b": [1, 2.5, -3], "a": "line\nbreak / slash", "c": .null]
        XCTAssertEqual(try value.compactJSON(), #"{"a":"line\nbreak / slash","b":[1,2.5,-3],"c":null}"#)
        XCTAssertEqual(try JSONValue.number(1.0).compactJSON(), "1")
    }

    func testRoundTrips() throws {
        let value: JSONValue = ["id": 12, "name": "x", "nested": ["list": [true, false, .null, 0.125]]]
        XCTAssertEqual(try JSONValue.parse(value.compactJSON()), value)
    }

    func testRejectsInvalidJSON() {
        XCTAssertThrowsError(try JSONValue.parse("{"))
        XCTAssertThrowsError(try JSONValue.parse(""))
    }

    func testRepeatedLiteralKeyKeepsTheLastValue() {
        let value: JSONValue = ["k": 1, "k": 2]
        XCTAssertEqual(value["k"], 2)
    }
}
