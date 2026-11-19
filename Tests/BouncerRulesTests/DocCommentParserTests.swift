import XCTest
@testable import BouncerRules

final class DocCommentParserTests: XCTestCase {
    // MARK: Swift

    func testSwiftReadsSingleAndListedParametersReturnsAndThrows() {
        let doc = """
            /// Does a thing.
            ///
            /// - Parameter first: The first.
            /// - Parameters:
            ///   - second: The second.
            ///   - third: The third.
            /// - Returns: A value.
            /// - Throws: An error.
            """
        let parsed = DocCommentParser.parse(doc, style: .swift)
        XCTAssertTrue(parsed.isStructured)
        XCTAssertEqual(parsed.parameterNames, ["first", "second", "third"])
        XCTAssertTrue(parsed.documentsReturn)
        XCTAssertTrue(parsed.documentsThrows)
    }

    func testSwiftSummaryOnlyIsUnstructured() {
        let parsed = DocCommentParser.parse("/// Does a thing.\n/// - Note: carefully.", style: .swift)
        XCTAssertFalse(parsed.isStructured)
        XCTAssertEqual(parsed.parameterNames, [])
    }

    func testSwiftListEndsAtTheNextTopLevelCallout() {
        let doc = "/// - Parameters:\n///   - a: A.\n/// - Returns: B.\n/// - b: not a parameter."
        XCTAssertEqual(DocCommentParser.parse(doc, style: .swift).parameterNames, ["a"])
    }

    // MARK: JSDoc

    func testJSDocReadsTypedOptionalAndDefaultedParameters() {
        let doc = """
            /**
             * Does a thing.
             * @param {Array<{a: string}>} items - The items.
             * @param [limit=10] The limit.
             * @param {Object} options
             * @param {boolean} options.debug Nested, so not a parameter.
             * @returns {number} The count.
             * @throws {Error} When empty.
             */
            """
        let parsed = DocCommentParser.parse(doc, style: .jsdoc)
        XCTAssertEqual(parsed.parameterNames, ["items", "limit", "options"])
        XCTAssertTrue(parsed.documentsReturn)
        XCTAssertTrue(parsed.documentsThrows)
    }

    func testJSDocThatInheritsIsUnstructured() {
        XCTAssertFalse(DocCommentParser.parse("/** @inheritDoc\n * @param x */", style: .jsdoc).isStructured)
        XCTAssertFalse(DocCommentParser.parse("/** Just a summary. */", style: .jsdoc).isStructured)
    }

    // MARK: Python

    func testPythonGoogleStyle() {
        let doc = """
            \"\"\"Summary.

                Args:
                    path (str): Where.
                        Continued description: not an entry.
                    *args: Extra.

                Returns:
                    The thing.

                Raises:
                    ValueError: When bad.
                \"\"\"
            """
        let parsed = DocCommentParser.parse(doc, style: .python)
        XCTAssertEqual(parsed.parameterNames, ["path", "args"])
        XCTAssertTrue(parsed.documentsReturn)
        XCTAssertTrue(parsed.documentsThrows)
    }

    func testPythonNumpyStyle() {
        let doc = """
            \"\"\"Summary.

                Parameters
                ----------
                x, y : int
                    The coordinates.
                scale : float

                Returns
                -------
                float
                \"\"\"
            """
        let parsed = DocCommentParser.parse(doc, style: .python)
        XCTAssertEqual(parsed.parameterNames, ["x", "y", "scale"])
        XCTAssertTrue(parsed.documentsReturn)
        XCTAssertFalse(parsed.documentsThrows)
    }

    func testPythonRestStyle() {
        let doc = "\"\"\"Summary.\n\n    :param str name: The name.\n    :param count: How many.\n    :rtype: int\n\"\"\""
        let parsed = DocCommentParser.parse(doc, style: .python)
        XCTAssertEqual(parsed.parameterNames, ["name", "count"])
        XCTAssertTrue(parsed.documentsReturn)
    }

    func testPythonUnreadableParameterSectionIsUnstructured() {
        let doc = "\"\"\"Summary.\n\n    Arguments:\n    a -- the first\n    b -- the second\n\"\"\""
        XCTAssertFalse(DocCommentParser.parse(doc, style: .python).isStructured)
    }
}
