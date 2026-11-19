import XCTest
import Foundation
import BouncerCore
@testable import BouncerSwiftAnalyzer

final class SwiftFunctionMeasureTests: XCTestCase {
    func testMeasuresComplexityAndLogicalLinesLikeTheRules() throws {
        let source = """
            func run(_ x: Int) -> Int {
                // a comment line isn't logical
                if x > 0 { return 1 }
                for _ in 0..<x where x > 2 { }
                return x == 3 ? 4 : 5
            }
            """
        let file = SourceFile(path: URL(fileURLWithPath: "/a.swift"), language: .swift, contents: source)
        let measured = try XCTUnwrap(SwiftSyntaxAnalyzer().measureFunctions(file: file))
        XCTAssertEqual(measured.map(\.name), ["run"])
        XCTAssertEqual(measured.first?.line, 1)
        let zero = { (key: String) in RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: [key: .int(0)])) }
        let settings = ["cyclomatic-complexity": zero("max"), "long-function": zero("maxLines")]
        let findings = try SwiftSyntaxAnalyzer().analyze(file: file, context: AnalysisContext(repoRoot: URL(fileURLWithPath: "/"), ruleSettings: settings))
        let messages = Set(findings.map(\.message))
        XCTAssertTrue(messages.contains("Function \"run\" has complexity \(measured[0].complexity), over the 0 limit."))
        XCTAssertTrue(messages.contains("Function \"run\" has \(measured[0].logicalLines ?? -1) logical lines, over the 0-line limit."))
    }
}
