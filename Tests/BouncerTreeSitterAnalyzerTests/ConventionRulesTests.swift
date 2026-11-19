import XCTest
import Foundation
import BouncerCore
@testable import BouncerTreeSitterAnalyzer

final class ConventionRulesTests: XCTestCase {
    private func findings(_ contents: String, file name: String = "a.ts") throws -> [Finding] {
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [:])
        let language = Language.from(fileExtension: URL(fileURLWithPath: name).pathExtension)
        let spec: TreeSitterLanguageSpec = [.python: .python, .go: .go][language] ?? .typescript
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/\(name)"), language: language, contents: contents)
        return try TreeSitterAnalyzer(spec: spec).analyze(file: file, context: context)
    }

    private func lines(of ruleID: String, in contents: String, file: String = "a.ts") throws -> [Int] {
        try findings(contents, file: file).filter { $0.ruleID == ruleID }.map(\.line)
    }

    func testTypeScriptElseAfterExitAndGlobals() throws {
        let contents = "let count = 0;\nexport let cache = {};\nconst LIMIT = 3;\nfunction f(a) {\n  if (a) { return 1; } else { return 2; }\n}\n"
        XCTAssertEqual(try lines(of: "else-after-return", in: contents), [5])
        XCTAssertEqual(try lines(of: "global-mutable-state", in: contents), [1, 2])
    }

    func testTypeScriptCallChainsTypeChecksAndTests() throws {
        let contents = """
            const a = xs.map((n) => n).filter((n) => n > 0).sort().reverse().slice(1).at(0);
            function f(v) { return v instanceof A || v instanceof B || v instanceof C; }
            it("does nothing", () => { f(1); });
            test("asserts", () => { expect(f(1)).toBe(true); });
            """
        let found = try findings(contents)
        XCTAssertEqual(found.filter { $0.ruleID == "long-message-chain" }.map(\.line), [1])
        XCTAssertTrue(found.contains { $0.ruleID == "type-check-chain" && $0.message.contains("3 runtime type checks") })
        XCTAssertEqual(found.filter { $0.ruleID == "test-without-assertions" }.map(\.line), [3])
    }

    func testTypeScriptDataClassesNamesAndStrings() throws {
        let contents = """
            import { a } from "./module";
            class Point { x = 0; y = 0; }
            class Counter { n = 0; step = 1; up() { this.n += this.step; } }
            function g(q, strName, isNotReady) { for (let i = 0; i < 1; i++) {} }
            log("./module"); log("./module"); log(`./module`);
            """
        let found = try findings(contents)
        XCTAssertEqual(found.filter { $0.ruleID == "data-class" }.map(\.line), [2])
        XCTAssertEqual(found.filter { $0.ruleID == "short-identifier" }.map(\.message), ["Name \"q\" is too short to say what it holds."])
        XCTAssertEqual(found.filter { $0.ruleID == "hungarian-notation" }.count, 1)
        XCTAssertEqual(found.filter { $0.ruleID == "negated-boolean-name" }.count, 1)
        XCTAssertTrue(found.contains { $0.ruleID == "duplicated-string-literal" && $0.message.contains("appears 3 times") })
    }

    func testPythonElseAfterExitGlobalChainsAndTests() throws {
        let contents = """
            def f(a):
                global COUNT
                if a:
                    return 1
                else:
                    return 2

            def test_nothing():
                f(1)

            def test_something():
                assert f(1) == 1
            """
        let found = try findings(contents, file: "a.py")
        XCTAssertEqual(found.filter { $0.ruleID == "else-after-return" }.map(\.line), [5])
        XCTAssertEqual(found.filter { $0.ruleID == "global-mutable-state" }.map(\.line), [2])
        XCTAssertEqual(found.filter { $0.ruleID == "test-without-assertions" }.map(\.line), [8])
    }

    func testGoElseAfterExitPackageVarsAndTests() throws {
        let contents = """
            package main

            var counter = 0

            func f(a bool) int {
            \tif a {
            \t\treturn 1
            \t} else {
            \t\treturn 2
            \t}
            }

            func TestNothing(t *testing.T) { f(true) }

            func TestSomething(t *testing.T) { if f(true) != 1 { t.Fatal("bad") } }
            """
        let found = try findings(contents, file: "a.go")
        XCTAssertEqual(found.filter { $0.ruleID == "else-after-return" }.map(\.line), [8])
        XCTAssertEqual(found.filter { $0.ruleID == "global-mutable-state" }.map(\.line), [3])
        XCTAssertEqual(found.filter { $0.ruleID == "test-without-assertions" }.map(\.line), [13])
    }
}
