import XCTest
import Foundation
import BouncerCore
@testable import BouncerTreeSitterAnalyzer

final class JavaScriptFamilyQualityRulesTests: XCTestCase {
    private let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [:])

    private func analyze(_ contents: String, file name: String = "a.ts", context: AnalysisContext? = nil) throws -> [Finding] {
        let language = Language.from(fileExtension: URL(fileURLWithPath: name).pathExtension)
        let spec: TreeSitterLanguageSpec = language == .javascript ? .javascript : .typescript
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/\(name)"), language: language, contents: contents)
        return try TreeSitterAnalyzer(spec: spec).analyze(file: file, context: context ?? self.context)
    }

    private func lines(of ruleID: String, in contents: String, file: String = "a.ts") throws -> [Int] {
        try analyze(contents, file: file).filter { $0.ruleID == ruleID }.map(\.line)
    }

    private func message(of ruleID: String, in contents: String, limit: (String, Int)) throws -> String? {
        let settings = RuleSettings(enabled: true, severity: .error, parameters: RuleParameters(values: [limit.0: .int(limit.1)]))
        let strict = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [ruleID: settings])
        return try analyze(contents, context: strict).first { $0.ruleID == ruleID }?.message
    }

    func testFlagsExplicitAnyButNotOtherTypes() throws {
        XCTAssertEqual(try lines(of: "explicit-any", in: "let a: any;\nlet b: unknown;\nlet c: number;\n"), [1])
    }

    func testFlagsNonNullAssertions() throws {
        XCTAssertEqual(try lines(of: "non-null-assertion", in: "const a = find()!;\nconst b = x !== y;\n"), [1])
    }

    func testFlagsEmptyCatchUnlessACommentExplainsIt() throws {
        let contents = "try { f(); } catch (e) {}\ntry { f(); } catch { /* best effort */ }\n"
        XCTAssertEqual(try lines(of: "empty-catch", in: contents), [1])
    }

    func testFlagsCodeAfterAJumpButNotHoistedFunctions() throws {
        let contents = "function f() {\n  return g();\n  function g() { return 1; }\n  console.info(1);\n}\n"
        XCTAssertEqual(try lines(of: "unreachable-code", in: contents), [4])
    }

    func testFlagsNestedTernariesOnce() throws {
        XCTAssertEqual(try lines(of: "nested-ternary", in: "const a = x ? 1 : y ? 2 : 0;\nconst b = x ? 1 : 0;\n"), [1])
    }

    func testFlagsOnlyUnnamedMagicNumbers() throws {
        let contents = """
            const TIMEOUT_MS = 5000;
            const config = { retries: 3 };
            function f(limit = 10, n: number) {}
            enum Status { NotFound = 404 }
            switch (code) { case 500: break; }
            setTimeout(run, 3000);
            """
        XCTAssertEqual(try lines(of: "magic-number", in: contents), [6])
    }

    func testCountsArrowAndMethodParameters() throws {
        XCTAssertEqual(try message(of: "long-parameter-list", in: "const f = (a, b, c) => a;\n", limit: ("maxParameters", 2)),
                       "Function \"f\" has 3 parameters, over the 2 limit.")
    }

    func testCountsOnlyThisFunctionsReturns() throws {
        let contents = "function f(x) {\n  xs.map((y) => { return y; });\n  if (x) { return 1; }\n  return 2;\n}\n"
        XCTAssertEqual(try message(of: "too-many-returns", in: contents, limit: ("maxReturns", 1)),
                       "Function \"f\" has 2 return statements, over the 1 limit.")
    }

    func testScoresCognitiveComplexityWithNestingAndElseChains() throws {
        // if (1) + nested for (2) + nested if (3) + mixed &&/|| run (2) + else if (1) + else (1) = 10
        let contents = """
            function f(a, b, c, xs) {
              if (a) {
                for (const x of xs) {
                  if (x && b || c) {}
                }
              } else if (b) {
              } else {
              }
            }
            """
        XCTAssertEqual(try message(of: "cognitive-complexity", in: contents, limit: ("max", 1)),
                       "Function \"f\" has cognitive complexity 10, over the 1 limit.")
    }

    func testMeasuresControlFlowNestingDepth() throws {
        let contents = "function f(a, xs) {\n  if (a) {\n    for (const x of xs) {\n      while (a) {}\n    }\n  }\n}\n"
        XCTAssertEqual(try message(of: "nesting-depth", in: contents, limit: ("maxDepth", 2)),
                       "Function \"f\" has control flow nested 3 deep, over the 2 limit.")
    }

    func testFlagsBooleanFlagParametersByTypeOrDefault() throws {
        let contents = "function f(a: boolean, b?: boolean, c: number, d = false, e = 0) {}\n"
        XCTAssertEqual(try message(of: "boolean-parameter", in: contents, limit: ("maxBooleanParameters", 0)),
                       "Function \"f\" has 3 boolean flag parameter(s), over the 0 limit.")
    }

    func testConstructorsStoringABooleanAreNotFlagArguments() throws {
        let contents = "class S {\n  constructor(private on: boolean) {}\n}\n"
        XCTAssertNil(try message(of: "boolean-parameter", in: contents, limit: ("maxBooleanParameters", 0)))
    }

    func testMeasuresLackOfCohesionIgnoringConstructorAndStaticMethods() throws {
        let contents = """
            class Mixed {
              cache: string[] = [];
              view = "";
              constructor() { this.cache = []; this.view = ""; }
              load() { this.cache.push("x"); }
              save = () => { this.persist(this.cache); };
              persist(items: string[]) {}
              render() { return this.view; }
              static make() { return new Mixed(); }
            }
            """
        XCTAssertEqual(try message(of: "lack-of-cohesion", in: contents, limit: ("maxGroups", 1)),
                       "Type \"Mixed\" splits into 2 unrelated method groups (LCOM4), over 1.")
    }

    func testFlagsTypeScriptAndJavaScriptPatternSmells() throws {
        let contents = """
            // @ts-ignore
            const a = b as unknown as string;
            var c = 1;
            eval(code);
            el.innerHTML = html;
            """
        let ids = Set(try analyze(contents).map(\.ruleID))
        XCTAssertTrue(ids.isSuperset(of: ["ts-ignore-without-reason", "ts-double-cast", "js-var", "js-eval", "js-raw-html"]))
    }

    func testAcceptsATsExpectErrorWithAReason() throws {
        XCTAssertEqual(try lines(of: "ts-ignore-without-reason", in: "// @ts-expect-error upstream types are wrong\n"), [])
    }

    func testRunsQualityRulesOnPlainJavaScript() throws {
        XCTAssertEqual(try lines(of: "empty-catch", in: "try { f(); } catch (e) {}\n", file: "a.js"), [1])
    }
}
