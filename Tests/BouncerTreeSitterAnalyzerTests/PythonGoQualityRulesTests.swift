import XCTest
import Foundation
import BouncerCore
@testable import BouncerTreeSitterAnalyzer

final class PythonGoQualityRulesTests: XCTestCase {
    private let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [:])

    private func analyze(_ contents: String, _ language: Language, context: AnalysisContext? = nil) throws -> [Finding] {
        let spec: TreeSitterLanguageSpec = language == .python ? .python : .go
        let name = language == .python ? "a.py" : "a.go"
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/\(name)"), language: language, contents: contents)
        return try TreeSitterAnalyzer(spec: spec).analyze(file: file, context: context ?? self.context)
    }

    private func lines(of ruleID: String, in contents: String, _ language: Language) throws -> [Int] {
        try analyze(contents, language).filter { $0.ruleID == ruleID }.map(\.line)
    }

    private func message(
        of ruleID: String, in contents: String, _ language: Language, limit: (String, Int)
    ) throws -> String? {
        let settings = RuleSettings(enabled: true, severity: .error, parameters: RuleParameters(values: [limit.0: .int(limit.1)]))
        let strict = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [ruleID: settings])
        return try analyze(contents, language, context: strict).first { $0.ruleID == ruleID }?.message
    }

    // MARK: Python

    func testPythonScoresCognitiveComplexityWithElifAndMixedBooleanOperators() throws {
        // if (1) + nested for (2) + nested if (3) + mixed and/or run (2) + elif (1) + else (1) = 10
        let contents = """
            def f(a, b, c, xs):
                if a:
                    for x in xs:
                        if x and b or c:
                            pass
                elif b:
                    pass
                else:
                    pass
            """
        XCTAssertEqual(try message(of: "cognitive-complexity", in: contents, .python, limit: ("max", 1)),
                       "Function \"f\" has cognitive complexity 10, over the 1 limit.")
    }

    func testPythonSkipsSelfAndSeparatorsWhenCountingParametersAndFlags() throws {
        let contents = "class C:\n    def m(self, a, b: bool, c=False, *, d=True):\n        pass\n"
        XCTAssertEqual(try message(of: "long-parameter-list", in: contents, .python, limit: ("maxParameters", 1)),
                       "Function \"m\" has 4 parameters, over the 1 limit.")
        XCTAssertEqual(try message(of: "boolean-parameter", in: contents, .python, limit: ("maxBooleanParameters", 0)),
                       "Function \"m\" has 3 boolean flag parameter(s), over the 0 limit.")
    }

    func testPythonFlagsExceptThatOnlyPasses() throws {
        let contents = """
            try:
                f()
            except ValueError:
                pass
            try:
                f()
            except ValueError:
                log()
            """
        XCTAssertEqual(try lines(of: "empty-catch", in: contents, .python), [3])
    }

    func testPythonFlagsUnreachableCodeAndNestedConditionalExpressions() throws {
        let contents = "def f(x, y):\n    a = 1 if x else (2 if y else 0)\n    return a\n    print(a)\n"
        XCTAssertEqual(try lines(of: "unreachable-code", in: contents, .python), [4])
        XCTAssertEqual(try lines(of: "nested-ternary", in: contents, .python), [2])
    }

    func testPythonFlagsOnlyUnnamedMagicNumbers() throws {
        let contents = """
            TIMEOUT = 30
            def g(n=5):
                h(retries=3)
                limits = {"max": 9}
                time.sleep(3600)
            """
        XCTAssertEqual(try lines(of: "magic-number", in: contents, .python), [5])
    }

    func testPythonMeasuresLackOfCohesionIgnoringInitAndDecoratedMethods() throws {
        let contents = """
            class Mixed:
                def __init__(self):
                    self.cache = []
                    self.view = ""
                def load(self):
                    self.cache.append(1)
                def save(self):
                    print(self.cache)
                def render(self):
                    return self.view
                @staticmethod
                def make():
                    return Mixed()
            """
        XCTAssertEqual(try message(of: "lack-of-cohesion", in: contents, .python, limit: ("maxGroups", 1)),
                       "Type \"Mixed\" splits into 2 unrelated method groups (LCOM4), over 1.")
    }

    func testPythonCountsOnlyItsOwnReturns() throws {
        let contents = "def f(x):\n    def g():\n        return 0\n    if x:\n        return 1\n    return 2\n"
        XCTAssertEqual(try message(of: "too-many-returns", in: contents, .python, limit: ("maxReturns", 1)),
                       "Function \"f\" has 2 return statements, over the 1 limit.")
    }

    // MARK: Go

    func testGoScoresElseAndElseIfThroughTheAlternativeField() throws {
        // if (1) + nested for (2) + nested if (3) + mixed &&/|| run (2) + else if (1) + else (1) = 10
        let contents = """
            package main

            func f(a, b, c bool, xs []int) {
            \tif a {
            \t\tfor _, x := range xs {
            \t\t\tif x > 0 && b || c {
            \t\t\t}
            \t\t}
            \t} else if b {
            \t} else {
            \t}
            }
            """
        XCTAssertEqual(try message(of: "cognitive-complexity", in: contents, .go, limit: ("max", 1)),
                       "Function \"f\" has cognitive complexity 10, over the 1 limit.")
        XCTAssertEqual(try message(of: "nesting-depth", in: contents, .go, limit: ("maxDepth", 2)),
                       "Function \"f\" has control flow nested 3 deep, over the 2 limit.")
    }

    func testGoCountsEachNameInAGroupedParameter() throws {
        let contents = "package main\n\nfunc f(a, b bool, c int) {}\n"
        XCTAssertEqual(try message(of: "long-parameter-list", in: contents, .go, limit: ("maxParameters", 2)),
                       "Function \"f\" has 3 parameters, over the 2 limit.")
        XCTAssertEqual(try message(of: "boolean-parameter", in: contents, .go, limit: ("maxBooleanParameters", 0)),
                       "Function \"f\" has 2 boolean flag parameter(s), over the 0 limit.")
    }

    func testGoFlagsUnreachableCodeAndOnlyUnnamedMagicNumbers() throws {
        let contents = """
            package main

            const timeout = 30

            func f(code int) int {
            \tlimit := 5
            \tswitch code {
            \tcase 404:
            \t\treturn limit
            \t}
            \ttime.Sleep(3600)
            \treturn 0
            \tprintln(limit)
            }
            """
        XCTAssertEqual(try lines(of: "magic-number", in: contents, .go), [11])
        XCTAssertEqual(try lines(of: "unreachable-code", in: contents, .go), [13])
    }

    func testGoCountsOnlyItsOwnReturns() throws {
        let contents = "package main\n\nfunc f(x int) int {\n\tg := func() int { return 0 }\n\tif x > 0 {\n\t\treturn 1\n\t}\n\treturn g()\n}\n"
        XCTAssertEqual(try message(of: "too-many-returns", in: contents, .go, limit: ("maxReturns", 1)),
                       "Function \"f\" has 2 return statements, over the 1 limit.")
    }
}
