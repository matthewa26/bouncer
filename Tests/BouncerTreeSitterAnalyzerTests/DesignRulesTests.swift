import XCTest
import Foundation
import BouncerCore
@testable import BouncerTreeSitterAnalyzer

final class DesignRulesTests: XCTestCase {
    private func findings(
        _ contents: String, file name: String = "a.ts", settings: [String: RuleSettings] = [:]
    ) throws -> [Finding] {
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: settings)
        let language = Language.from(fileExtension: URL(fileURLWithPath: name).pathExtension)
        let spec: TreeSitterLanguageSpec = [.python: .python, .go: .go, .javascript: .javascript][language] ?? .typescript
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/\(name)"), language: language, contents: contents)
        return try TreeSitterAnalyzer(spec: spec).analyze(file: file, context: context)
    }

    private func messages(
        of ruleID: String, in contents: String, file: String = "a.ts", settings: [String: RuleSettings] = [:]
    ) throws -> [String] {
        try findings(contents, file: file, settings: settings).filter { $0.ruleID == ruleID }.map(\.message)
    }

    private func setting(_ ruleID: String, _ values: [String: RuleParameterValue] = [:]) -> [String: RuleSettings] {
        [ruleID: RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: values))]
    }

    // MARK: npath-complexity

    func testNPathAcrossLanguages() throws {
        let typescript = """
            function f(a, b, c) {
              if (a) { g(); }
              if (b || c) { g(); } else { h(); }
              for (const x of a) { g(x); }
              switch (a) { case 1: g(); break; case 2: h(); break; }
              try { g(); } catch (e) { h(); }
              return a ? b : c;
            }
            """
        let python = """
            def f(a, b):
                if a:
                    g()
                elif b:
                    h()
                while a:
                    g()
                match a:
                    case 1:
                        g()
                    case _:
                        h()
            """
        let go = "package p\nfunc f(a, b bool) {\n\tif a { g() } else if b { h() }\n\tfor a { g() }\n\tswitch { case a: g() }\n}\n"
        let settings = setting("npath-complexity", ["max": .int(1)])
        XCTAssertEqual(try messages(of: "npath-complexity", in: typescript, settings: settings),
                       ["Function \"f\" has NPath complexity 144, over the 1 limit."])
        XCTAssertEqual(try messages(of: "npath-complexity", in: python, file: "a.py", settings: settings),
                       ["Function \"f\" has NPath complexity 12, over the 1 limit."])
        XCTAssertEqual(try messages(of: "npath-complexity", in: go, file: "a.go", settings: settings),
                       ["Function \"f\" has NPath complexity 12, over the 1 limit."])
        XCTAssertEqual(try messages(of: "npath-complexity", in: typescript), [])
    }

    // MARK: halstead-complexity and maintainability-index

    func testHalsteadCountsLeavesAndStringsWhole() throws {
        let contents = "function f(a) {\n  const s = \"a b c d e f g\";\n  return a + s;\n}\n"
        let found = try messages(of: "halstead-complexity", in: contents, settings: setting("halstead-complexity", ["maxVolume": .int(1)]))
        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(found.first?.contains("Halstead volume 34,") ?? false, found.first ?? "")
    }

    func testMaintainabilityIndexOnPython() throws {
        let body = (1...300).map { "    v\($0) = a * \($0) + b - \($0 % 7)" }.joined(separator: "\n")
        let contents = "def big(a, b):\n\(body)\n\ndef small():\n    return 1\n"
        let found = try messages(of: "maintainability-index", in: contents, file: "a.py")
        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(found.first?.hasPrefix("Function \"big\" has maintainability index ") ?? false)
    }

    // MARK: arrow-code

    func testArrowCodeAcrossLanguages() throws {
        let typescript = "function f(a) {\n  if (a) {\n    if (a.b) {\n      if (a.c) {\n        g();\n      }\n    }\n  }\n}\n"
        let python = "def f(a):\n    for x in a:\n        if x:\n            if x.b:\n                if x.c:\n                    g()\n"
        let go = "package p\nfunc f(a T) {\n\tif a.x {\n\t\tif a.y {\n\t\t\tif a.z {\n\t\t\t\tg()\n\t\t\t}\n\t\t}\n\t}\n}\n"
        XCTAssertEqual(try messages(of: "arrow-code", in: typescript).count, 1)
        XCTAssertEqual(try messages(of: "arrow-code", in: python, file: "a.py").count, 1)
        XCTAssertEqual(try messages(of: "arrow-code", in: go, file: "a.go").count, 1)
    }

    func testArrowCodeSkipsElseAndCodeAfter() throws {
        let withElse = "function f(a) {\n  if (a) { if (a.b) { if (a.c) { g(); } } } else { h(); }\n}\n"
        let codeAfter = "def f(a):\n    if a:\n        if a.b:\n            if a.c:\n                g()\n    h()\n"
        XCTAssertEqual(try messages(of: "arrow-code", in: withElse), [])
        XCTAssertEqual(try messages(of: "arrow-code", in: codeAfter, file: "a.py"), [])
    }

    // MARK: too-many-loop-jumps

    func testLoopJumpsHonorLabelsAndSwitchBreaks() throws {
        let typescript = """
            function f(xs) {
              outer: for (const x of xs) {
                if (x === 1) continue;
                switch (x) { case 2: break; default: break; }
                for (const y of xs) {
                  if (y === x) continue outer;
                  if (y > x) break outer;
                }
              }
            }
            """
        let go = "package p\nfunc f(xs []int) {\n\tfor _, x := range xs {\n\t\tswitch x {\n\t\tcase 1:\n\t\t\tbreak\n\t\t}\n"
            + "\t\tif x == 2 {\n\t\t\tcontinue\n\t\t}\n\t\tif x == 3 {\n\t\t\tbreak\n\t\t}\n\t}\n}\n"
        let settings = setting("too-many-loop-jumps", ["maxJumps": .int(1)])
        XCTAssertEqual(try messages(of: "too-many-loop-jumps", in: typescript, settings: settings),
                       ["Function \"f\" has a loop with 3 break/continue statements, over the 1 limit."])
        XCTAssertEqual(try messages(of: "too-many-loop-jumps", in: go, file: "a.go", settings: settings),
                       ["Function \"f\" has a loop with 2 break/continue statements, over the 1 limit."])
    }

    // MARK: recursion-without-base-case

    func testRecursionWithoutBaseCaseAcrossLanguages() throws {
        let typescript = """
            function spin(n) { return spin(n + 1); }
            function fact(n) { return n <= 1 ? 1 : n * fact(n - 1); }
            function poll() { setTimeout(() => poll(), 10); }
            class A { run() { this.run(); } stop() { stop(); } }
            """
        let python = "def spin(n):\n    return spin(n + 1)\n\nclass A:\n    def walk(self, xs):\n"
            + "        return [self.walk(x) for x in xs]\n    def go(self):\n        self.go()\n"
        let go = "package p\nfunc spin(n int) int { return spin(n + 1) }\nfunc walk(n int) { if n > 0 { walk(n - 1) } }\n"
        XCTAssertEqual(try findings(typescript).filter { $0.ruleID == "recursion-without-base-case" }.map(\.line), [1, 4])
        XCTAssertEqual(try findings(python, file: "a.py").filter { $0.ruleID == "recursion-without-base-case" }
            .map(\.line), [1, 7])
        XCTAssertEqual(try findings(go, file: "a.go").filter { $0.ruleID == "recursion-without-base-case" }.map(\.line), [2])
    }

    // MARK: class rules

    func testWeightedMethodsAndClassCohesionOnTypeScript() throws {
        let contents = """
            class Split {
              constructor() { this.a = 0; this.b = 0; }
              readA() { return this.a; }
              bumpA() { if (this.a > 0) { this.a += 1; } }
              readB() { return this.b; }
              bumpB() { if (this.b > 0) { this.b += 1; } }
            }
            """
        XCTAssertEqual(try messages(of: "weighted-methods", in: contents, settings: setting("weighted-methods", ["max": .int(5)])),
                       ["Type \"Split\" has weighted methods (WMC) 7 across 5 methods, over the 5 limit."])
        XCTAssertEqual(try messages(of: "class-cohesion", in: contents, settings: setting("class-cohesion", ["minTCC": .double(0.5)])),
                       ["Type \"Split\" has tight class cohesion 33% and loose class cohesion 33% across 4 methods, "
                        + "under the minimums (TCC 50%, LCC 0%)."])
        let lcom2 = setting("lack-of-cohesion", ["variant": .string("lcom2"), "maxPairs": .int(1)])
        XCTAssertEqual(try messages(of: "lack-of-cohesion", in: contents, settings: lcom2),
                       ["Type \"Split\" has 2 method pairs sharing no field (LCOM2), over 1."])
    }

    func testMiddleManOnPythonAndLazyClassOnTypeScript() throws {
        let python = """
            class Proxy:
                def __init__(self, inner):
                    self._inner = inner
                def get(self, key):
                    \"\"\"Gets.\"\"\"
                    return self._inner.get(key)
                def put(self, key, value):
                    self._inner.put(key, value)
                async def close(self):
                    await self._inner.close()
            """
        XCTAssertEqual(try messages(of: "middle-man", in: python, file: "a.py"),
                       ["Type \"Proxy\" only forwards 3 of its 3 methods to \"_inner\"; let callers use it directly."])
        let typescript = """
            class Helper { run(x) { return x + 1; } }
            export class Exported { run(x) { return x + 1; } }
            class Derived extends Base { run(x) { return x + 1; } }
            class Stateful { run(x) { return this.y + x; } }
            """
        XCTAssertEqual(try findings(typescript, settings: setting("lazy-class")).filter { $0.ruleID == "lazy-class" }
            .map(\.line), [1])
        XCTAssertEqual(try messages(of: "lazy-class", in: typescript), [])
    }

    // MARK: law-of-demeter

    func testLawOfDemeterOnTypeScriptPythonAndGo() throws {
        let typescript = """
            const city = order.customer().address().region().name();
            const names = users.filter(u => u.ok).map(u => u.name).join(",");
            this.props.navigation.navigate("Home");
            """
        let python = "import pip\nx = pip.internal.utils.misc.ensure()\ny = self.parser.tokenizer.stream.reader.change()\n"
        let go = "package p\nfunc f() { g.m.p.ptr().status = 1 }\n"
        let settings = setting("law-of-demeter")
        XCTAssertEqual(try findings(typescript, settings: settings).filter { $0.ruleID == "law-of-demeter" }.map(\.line), [1])
        XCTAssertEqual(try findings(python, file: "a.py", settings: settings).filter { $0.ruleID == "law-of-demeter" }
            .map(\.line), [3])
        XCTAssertEqual(try findings(go, file: "a.go", settings: settings).filter { $0.ruleID == "law-of-demeter" }
            .map(\.line), [2])
        XCTAssertEqual(try messages(of: "law-of-demeter", in: typescript), [])
    }

    // MARK: doc completeness

    func testJSDocCompletenessAndStaleness() throws {
        let contents = """
            /**
             * Loads.
             * @param {string} path - Where.
             * @param {number} retry - Renamed since.
             */
            export function load(path, retries) {
              if (!path) { throw new Error("no path"); }
              return read(path);
            }

            /** Summary only. */
            function quiet(a) { return a; }

            /**
             * Destructured.
             * @param {Object} options
             */
            function configure({ debug }) { try { if (!debug) { throw new Error("off"); } } catch (e) { log(e); } }
            """
        XCTAssertEqual(try messages(of: "incomplete-documentation", in: contents),
                       ["Doc comment for \"load\" doesn't describe parameter \"retries\", the return value, "
                        + "and what it throws."])
        XCTAssertEqual(try messages(of: "stale-documentation", in: contents),
                       ["Doc comment for \"load\" describes \"retry\", not in its signature."])
    }

    func testPythonDocstringCompletenessAndStaleness() throws {
        let contents = """
            def load(path, retries=3, *args, **kwargs):
                \"\"\"Loads.

                Args:
                    path: Where.
                    timeout: Passed through kwargs.
                \"\"\"
                if not path:
                    raise ValueError("no path")
                return read(path)

            def save(self, value):
                \"\"\"Saves.

                :param value: The value.
                :param old: Gone.
                \"\"\"
                try:
                    write(value)
                except OSError:
                    pass

            class A:
                @property
                def size(self):
                    \"\"\"The size.

                    Args:
                        none: Nothing.
                    \"\"\"
                    return 1
            """
        XCTAssertEqual(try messages(of: "incomplete-documentation", in: contents, file: "a.py"),
                       ["Doc comment for \"load\" doesn't describe parameter \"retries\", the return value, "
                        + "and what it throws."])
        XCTAssertEqual(try messages(of: "stale-documentation", in: contents, file: "a.py"),
                       ["Doc comment for \"save\" describes \"old\", not in its signature.",
                        "Doc comment for \"size\" describes \"none\", not in its signature."])
    }

    func testGoDocCommentsAreNotChecked() throws {
        let contents = "package p\n\n// Load loads.\n// - Parameter x: stale.\nfunc Load(path string) error { return nil }\n"
        XCTAssertEqual(try messages(of: "stale-documentation", in: contents, file: "a.go"), [])
    }

    // MARK: oversized-test

    func testOversizedTestCountsAssertionsInTestFiles() throws {
        let asserts = (1...4).map { "  expect(f(\($0))).toBe(\($0));" }.joined(separator: "\n")
        let typescript = "it(\"works\", () => {\n\(asserts)\n});\n"
        let python = "def test_many():\n" + (1...4).map { "    assert f(\($0)) == \($0)" }.joined(separator: "\n") + "\n"
        let settings = setting("oversized-test", ["maxAssertions": .int(3)])
        XCTAssertEqual(try messages(of: "oversized-test", in: typescript, file: "a.test.ts", settings: settings),
                       ["Test has 4 assertions (limit 3); split it into focused tests."])
        XCTAssertEqual(try messages(of: "oversized-test", in: python, file: "test_a.py", settings: settings),
                       ["Test \"test_many\" has 4 assertions (limit 3); split it into focused tests."])
        XCTAssertEqual(try messages(of: "oversized-test", in: python, file: "a.py", settings: settings), [])
    }
}
