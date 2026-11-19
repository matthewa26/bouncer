import XCTest
@testable import BouncerRules

final class TypeWordsTests: XCTestCase {
    func testClassifiesTypeTextAcrossLanguages() {
        XCTAssertEqual(TypeWords.categories(of: "[User]"), [.array])
        XCTAssertEqual(TypeWords.categories(of: "[String: [Int]]?"), [.dictionary])
        XCTAssertEqual(TypeWords.categories(of: ": string[]"), [.array])
        XCTAssertEqual(TypeWords.categories(of: "[]string"), [.array])
        XCTAssertEqual(TypeWords.categories(of: "map[string]int"), [.dictionary])
        XCTAssertEqual(TypeWords.categories(of: "Dict[str, int]"), [.dictionary])
        XCTAssertEqual(TypeWords.categories(of: "Optional[bool]"), [.boolean])
        XCTAssertEqual(TypeWords.categories(of: ": boolean | undefined"), [.boolean])
        XCTAssertEqual(TypeWords.categories(of: "number"), [.integer, .float])
        XCTAssertEqual(TypeWords.categories(of: "Set<Int>"), [.set])
        XCTAssertEqual(TypeWords.categories(of: "User"), [])
        XCTAssertEqual(TypeWords.categories(of: nil), [])
    }

    func testFindsTypeWordSuffixesAsWholeWords() {
        XCTAssertEqual(TypeWords.typeSuffix(of: "userList")?.word, "List")
        XCTAssertEqual(TypeWords.typeSuffix(of: "user_dict")?.word, "dict")
        XCTAssertEqual(TypeWords.typeSuffix(of: "userIDSet")?.word, "Set")
        XCTAssertNil(TypeWords.typeSuffix(of: "list"))
        XCTAssertNil(TypeWords.typeSuffix(of: "playlist"))
        XCTAssertNil(TypeWords.typeSuffix(of: "userName"))
    }

    func testSplitsNamesIntoWords() {
        XCTAssertEqual(TypeWords.words(of: "isReady"), ["is", "ready"])
        XCTAssertEqual(TypeWords.words(of: "_is_ready"), ["is", "ready"])
        XCTAssertEqual(TypeWords.words(of: "tokenIsMissing"), ["token", "is", "missing"])
    }
}
