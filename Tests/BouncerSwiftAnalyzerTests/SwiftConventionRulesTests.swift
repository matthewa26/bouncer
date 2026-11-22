import XCTest
import Foundation
import BouncerCore
@testable import BouncerSwiftAnalyzer

final class SwiftConventionRulesTests: XCTestCase {
    private func findings(_ contents: String, settings: [String: RuleSettings] = [:]) throws -> [Finding] {
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: settings)
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.swift"), language: .swift, contents: contents)
        return try SwiftSyntaxAnalyzer().analyze(file: file, context: context)
    }

    private func lines(of ruleID: String, in contents: String) throws -> [Int] {
        try findings(contents).filter { $0.ruleID == ruleID }.map(\.line)
    }

    private func limit(_ ruleID: String, _ parameter: String, _ value: Int) -> [String: RuleSettings] {
        [ruleID: RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: [parameter: .int(value)]))]
    }

    func testFlagsElseAfterABranchThatAlwaysExits() throws {
        let contents = "func f(a: Bool) -> Int {\n    if a { return 1 } else { return 2 }\n}\nfunc g(a: Bool) {\n    if a { print(1) } else { print(2) }\n}\n"
        XCTAssertEqual(try lines(of: "else-after-return", in: contents), [2])
    }

    func testFlagsStoredGlobalAndStaticVarsButNotConstantsOrComputedProperties() throws {
        let contents = """
            var counter = 0
            let limit = 3
            enum Cache {
                static var shared: [String] = []
                static let name = "x"
                static var isEmpty: Bool { shared.isEmpty }
            }
            """
        XCTAssertEqual(try lines(of: "global-mutable-state", in: contents), [1, 4])
    }

    func testMeasuresTheOutermostCallChain() throws {
        let contents = "let a = [1].map { $0 }.filter { $0 > 0 }.sorted().first(where: { _ in true })\n"
        let found = try findings(contents, settings: limit("long-message-chain", "maxCalls", 3))
        XCTAssertEqual(found.filter { $0.ruleID == "long-message-chain" }.map(\.message),
                       ["Long chain of calls (Law of Demeter); name the intermediate results. (4 calls, over 3)"])
    }

    func testFlagsOnlyTestsWithoutAssertions() throws {
        let contents = """
            final class T: XCTestCase {
                func testNothing() { _ = 1 }
                func testXCT() { XCTAssertEqual(1, 1) }
                func testHelper() { assertValid(1) }
                @Test func swiftTesting() { #expect(true) }
                @Test func swiftTestingEmpty() { _ = 1 }
                func helper() {}
            }
            """
        XCTAssertEqual(try lines(of: "test-without-assertions", in: contents), [2, 6])
    }

    func testCountsIsAndConditionalCastsAsTypeChecks() throws {
        let contents = "func f(v: Any) {\n    if v is Int { }\n    if let s = v as? String { _ = s }\n    switch v { case is Double: break; default: break }\n}\n"
        let found = try findings(contents, settings: limit("type-check-chain", "maxTypeChecks", 2))
        XCTAssertTrue(found.contains { $0.ruleID == "type-check-chain" && $0.message.contains("3 runtime type checks") })
    }

    func testFlagsDataClassesButNotStructsOrClassesWithBehavior() throws {
        let contents = """
            final class Point { var x = 0; var y = 0 }
            struct Size { var w = 0; var h = 0 }
            final class Counter { var n = 0; var step = 1; func up() { n += step } }
            """
        XCTAssertEqual(try lines(of: "data-class", in: contents), [1])
    }

    func testFlagsShortNegatedAndHungarianNames() throws {
        let contents = "func f(q: Int, i: Int, strName: String, isNotReady: Bool, notified: Bool, noOp: Bool) {}\n"
        let found = try findings(contents)
        XCTAssertEqual(found.filter { $0.ruleID == "short-identifier" }.map(\.message), ["Name \"q\" is too short to say what it holds."])
        XCTAssertEqual(found.filter { $0.ruleID == "negated-boolean-name" }.count, 1)
        XCTAssertEqual(found.filter { $0.ruleID == "hungarian-notation" }.count, 1)
    }

    func testFlagsStringsRepeatedThreeTimesButNotInterpolatedOnes() throws {
        let contents = "let a = \"loading\"\nlet b = \"loading\"\nlet c = \"loading\"\nlet d = \"\\(a) x\"\nlet e = \"\\(a) x\"\nlet f = \"\\(a) x\"\n"
        XCTAssertEqual(try lines(of: "duplicated-string-literal", in: contents), [1])
    }

    func testOrdersRepeatedStringsOnTheSameLineByText() throws {
        let line = "f(\"zebra-value\", \"apple-value\")\n"
        let messages = try findings(line + line + line).filter { $0.ruleID == "duplicated-string-literal" }.map(\.message)
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages[0].contains("apple-value"))
    }
}
