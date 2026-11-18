import XCTest
import Foundation
import BouncerCore
@testable import BouncerSwiftAnalyzer

final class SwiftQualityRulesTests: XCTestCase {
    private let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [:])

    private func lines(of ruleID: String, in contents: String, context: AnalysisContext? = nil) throws -> [Int] {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.swift"), language: .swift, contents: contents)
        return try SwiftSyntaxAnalyzer().analyze(file: file, context: context ?? self.context)
            .filter { $0.ruleID == ruleID }.map(\.line)
    }

    private func message(of ruleID: String, in contents: String, limit: (String, Int)) throws -> String? {
        let settings = RuleSettings(enabled: true, severity: .error, parameters: RuleParameters(values: [limit.0: .int(limit.1)]))
        let strict = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [ruleID: settings])
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.swift"), language: .swift, contents: contents)
        return try SwiftSyntaxAnalyzer().analyze(file: file, context: strict).first { $0.ruleID == ruleID }?.message
    }

    func testFlagsForceCastButNotConditionalCast() throws {
        XCTAssertEqual(try lines(of: "force-cast", in: "let a = x as! Int\nlet b = x as? Int\n"), [1])
    }

    func testFlagsImplicitlyUnwrappedOptionals() throws {
        XCTAssertEqual(try lines(of: "implicitly-unwrapped-optional", in: "var a: String!\nvar b: String?\n"), [1])
    }

    func testFlagsEmptyCatchUnlessACommentExplainsIt() throws {
        let contents = "do { try f() } catch {}\ndo { try f() } catch { /* offline is fine */ }\n"
        XCTAssertEqual(try lines(of: "empty-catch", in: contents), [1])
    }

    func testFlagsTheFirstStatementAfterAReturn() throws {
        let contents = "func f() -> Int {\n    return 1\n    let dead = 2\n    _ = dead\n}\n"
        XCTAssertEqual(try lines(of: "unreachable-code", in: contents), [3])
    }

    func testFlagsChainedAndParenthesizedNestedTernaries() throws {
        let contents = "let a = x ? 1 : y ? 2 : 0\nlet b = x ? (y ? 1 : 2) : 0\nlet c = x ? 1 : 2\n"
        XCTAssertEqual(try lines(of: "nested-ternary", in: contents), [1, 2])
    }

    func testFlagsOnlyUnnamedMagicNumbers() throws {
        let contents = """
            let secondsPerHour = 60 * 60
            func f(timeout: Int = 30) {}
            let limits = ["max": 40]
            f(timeout: 45)
            if x > 86400 { }
            switch code { case 404: break; default: break }
            """
        XCTAssertEqual(try lines(of: "magic-number", in: contents), [5])
    }

    func testCountsParameters() throws {
        let contents = "func f(a: Int, b: Int, c: Int) {}\n"
        XCTAssertEqual(try message(of: "long-parameter-list", in: contents, limit: ("maxParameters", 2)),
                       "Function \"f\" has 3 parameters, over the 2 limit.")
    }

    func testCountsOnlyThisFunctionsReturns() throws {
        let contents = "func f(x: Int) -> Int {\n    let g = { return 0 }\n    if x > 0 { return 1 }\n    return g()\n}\n"
        XCTAssertEqual(try message(of: "too-many-returns", in: contents, limit: ("maxReturns", 1)),
                       "Function \"f\" has 2 return statements, over the 1 limit.")
    }

    func testScoresCognitiveComplexityWithNestingAndElseChains() throws {
        // if (1) + nested for (2) + nested if (3) + else if (1) + else (1) + mixed &&/|| run (2) = 10
        let contents = """
            func f(a: Bool, b: Bool, c: Bool, xs: [Int]) {
                if a {
                    for x in xs {
                        if x > 0 && b || c { }
                    }
                } else if b {
                } else {
                }
            }
            """
        XCTAssertEqual(try message(of: "cognitive-complexity", in: contents, limit: ("max", 1)),
                       "Function \"f\" has cognitive complexity 10, over the 1 limit.")
    }

    func testMeasuresControlFlowNestingDepth() throws {
        let contents = "func f(a: Bool, xs: [Int]) {\n    if a {\n        for _ in xs {\n            while a { }\n        }\n    }\n}\n"
        XCTAssertEqual(try message(of: "nesting-depth", in: contents, limit: ("maxDepth", 2)),
                       "Function \"f\" has control flow nested 3 deep, over the 2 limit.")
    }

    func testFlagsSwiftPatternSmells() throws {
        let contents = "fatalError(\"x\")\nfinal class A: @unchecked Sendable {}\nprint(1)\n_ = try? f()\n"
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.swift"), language: .swift, contents: contents)
        let ids = Set(try SwiftSyntaxAnalyzer().analyze(file: file, context: context).map(\.ruleID))
        XCTAssertTrue(ids.isSuperset(of: ["swift-fatal-error", "swift-unchecked-sendable", "swift-debug-print", "swift-discarded-try"]))
    }
}
