import XCTest
import Foundation
import BouncerCore
@testable import BouncerHeuristicAnalyzer

final class HeuristicFunctionMeasureTests: XCTestCase {
    func testMeasuresUnnamedFunctionBlocks() throws {
        let source = "int pick(int a) {\n    if (a > 1) {\n        return 2;\n    }\n    return 3;\n}\n"
        let file = SourceFile(path: URL(fileURLWithPath: "/a.c"), language: .c, contents: source)
        let measured = try XCTUnwrap(HeuristicAnalyzer(language: .c).measureFunctions(file: file))
        XCTAssertEqual(measured.count, 1)
        XCTAssertNil(measured[0].name)
        XCTAssertEqual(measured[0].complexity, 2)
    }
}
