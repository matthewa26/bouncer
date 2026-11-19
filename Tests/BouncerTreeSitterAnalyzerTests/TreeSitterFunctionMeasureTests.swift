import XCTest
import Foundation
import BouncerCore
@testable import BouncerTreeSitterAnalyzer

final class TreeSitterFunctionMeasureTests: XCTestCase {
    func testMeasuresNamedAndAnonymousTypeScriptFunctions() throws {
        let source = "export function pick(a: number) {\n  if (a > 1) { return 2; }\n  return 3;\n}\nexport const f = () => 1;\n"
        let file = SourceFile(path: URL(fileURLWithPath: "/a.ts"), language: .typescript, contents: source)
        let measured = try XCTUnwrap(TreeSitterAnalyzer(spec: .typescript).measureFunctions(file: file))
        let pick = try XCTUnwrap(measured.first { $0.name == "pick" })
        XCTAssertEqual(pick.complexity, 2)
        XCTAssertEqual(pick.logicalLines, 4)
    }
}
