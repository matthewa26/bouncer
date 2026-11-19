import XCTest
import Foundation
import BouncerCore
@testable import BouncerTreeSitterAnalyzer

final class ShapeRulesTests: XCTestCase {
    private func findings(
        _ contents: String, file name: String = "a.ts", settings: [String: RuleSettings] = [:]
    ) throws -> [Finding] {
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: settings)
        let language = Language.from(fileExtension: URL(fileURLWithPath: name).pathExtension)
        let spec: TreeSitterLanguageSpec = [.python: .python, .go: .go, .javascript: .javascript][language] ?? .typescript
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/\(name)"), language: language, contents: contents)
        return try TreeSitterAnalyzer(spec: spec).analyze(file: file, context: context)
    }

    private func lines(
        of ruleID: String, in contents: String, file: String = "a.ts", settings: [String: RuleSettings] = [:]
    ) throws -> [Int] {
        try findings(contents, file: file, settings: settings).filter { $0.ruleID == ruleID }.map(\.line)
    }

    private func setting(_ ruleID: String, _ values: [String: RuleParameterValue] = [:]) -> [String: RuleSettings] {
        [ruleID: RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: values))]
    }

    // MARK: TypeScript / JavaScript

    func testTypeScriptLargeTypesIncludeInterfacesAndEnums() throws {
        let contents = """
            interface Shape {
              a: number;
              b: number;
              c: number;
            }
            enum E { A }
            class C {
              x = 1;
              y = 2;
              z = 3;
            }
            """
        let settings = setting("large-type", ["maxLines": .int(4)])
        XCTAssertEqual(try lines(of: "large-type", in: contents, settings: settings), [1, 7])
    }

    func testTypeScriptLongClosureSkipsNamedSuiteAndImmediatelyInvokedFunctions() throws {
        let contents = """
            xs.forEach((x) => {
              a(x);
              b(x);
              c(x);
            });
            const named = () => {
              a();
              b();
              c();
            };
            describe("suite", () => {
              a();
              b();
              c();
            });
            (function () {
              a();
              b();
              c();
            })();
            """
        let settings = setting("long-closure", ["maxLines": .int(3)])
        XCTAssertEqual(try lines(of: "long-closure", in: contents, settings: settings), [1])
    }

    func testTypeScriptLongBooleanExpressionCountsTheWholeChainOnce() throws {
        let contents = """
            const ok = a && b || c;
            const long = a && (b || !(c && d)) && e;
            """
        let found = try findings(contents).filter { $0.ruleID == "long-boolean-expression" }
        XCTAssertEqual(found.map(\.line), [2])
        XCTAssertTrue(found.first?.message.hasSuffix("(5 operands, over 4)") ?? false)
    }

    func testTypeScriptLocalsGenericsAndLongIdentifiers() throws {
        let long = String(repeating: "a", count: 51)
        let contents = """
            function f<A, B, C, D, E>(): void {
              const one = 1, two = 2;
              const { three, four } = props;
              const inner = () => { const hidden = 1; };
            }
            type Pair<A, B> = [A, B];
            let \(long) = 1;
            """
        let found = try findings(contents, settings: setting("too-many-locals", ["maxLocals": .int(3)]))
        XCTAssertEqual(found.filter { $0.ruleID == "too-many-locals" }.map(\.message),
                       ["Function \"f\" has 4 local variables, over the 3 limit."])
        XCTAssertEqual(found.filter { $0.ruleID == "too-many-generic-parameters" }.map(\.line), [1])
        XCTAssertEqual(found.filter { $0.ruleID == "long-identifier" }.map(\.line), [7])
    }

    func testTypeScriptTypedNameRules() throws {
        let contents = """
            class Store {
              private loading = false;
              isReady: boolean = true;
              userList: string[] = [];
              userMap = new Map<string, number>();
              items: number[] = [];
            }
            """
        XCTAssertEqual(try lines(of: "type-in-name", in: contents), [4, 5])
        XCTAssertEqual(try lines(of: "boolean-name-prefix", in: contents), [])
        XCTAssertEqual(try lines(of: "boolean-name-prefix", in: contents, settings: setting("boolean-name-prefix")), [2])
    }

    func testTypeScriptFileNameMismatchUsesKebabCaseAndExports() throws {
        let service = "export class UserService {}\n"
        XCTAssertEqual(try lines(of: "file-name-mismatch", in: service, file: "user-service.ts"), [])
        XCTAssertEqual(try lines(of: "file-name-mismatch", in: service, file: "user.service.ts"), [])
        XCTAssertEqual(try lines(of: "file-name-mismatch", in: service, file: "accounts.ts"), [1])
        XCTAssertEqual(try lines(of: "file-name-mismatch", in: "export interface IUser {}\n", file: "user.ts"), [])
        let others: [(file: String, contents: String)] = [
            ("accounts.ts", "class UserService {}\n"),
            ("accounts.ts", "export class UserService {}\nexport function load() {}\n"),
            ("accounts.test.ts", "export class UserService {}\n"),
            ("index.ts", "export class UserService {}\n")
        ]
        for (file, contents) in others {
            XCTAssertEqual(try lines(of: "file-name-mismatch", in: contents, file: file), [], file)
        }
    }

    // MARK: Python

    func testPythonSizeRules() throws {
        let contents = """
            class Widget:
                enabled = False

                def f(self, a: bool, b=True, user_list: list = None):
                    one, two = 1, 2
                    found = False
                    found = True
                    g = lambda: (one and two)
                    return a and b or (one and not (a or two)) and found
            """
        let found = try findings(contents, file: "w.py", settings: setting("too-many-locals", ["maxLocals": .int(3)]))
        XCTAssertEqual(found.filter { $0.ruleID == "too-many-locals" }.map(\.message),
                       ["Function \"f\" has 4 local variables, over the 3 limit."])
        XCTAssertEqual(found.filter { $0.ruleID == "long-boolean-expression" }.map(\.line), [9])
        XCTAssertEqual(found.filter { $0.ruleID == "type-in-name" }.map(\.line), [4])
        XCTAssertEqual(found.filter { $0.ruleID == "file-name-mismatch" }.map(\.line), [])
    }

    func testPythonBooleanNamesCountOnlyTheFirstAssignmentAndSkipConstants() throws {
        let contents = "DEBUG = False\nfound = False\nfound = True\nis_ready = True\n"
        let settings = setting("boolean-name-prefix")
        XCTAssertEqual(try lines(of: "boolean-name-prefix", in: contents, file: "m.py", settings: settings), [2])
    }

    func testPythonEqualityMethodsAreExemptFromLongBooleanExpression() throws {
        let contents = """
            class P:
                def __eq__(self, o):
                    return self.a == o.a and self.b == o.b and self.c == o.c and self.d == o.d and self.e == o.e
            """
        XCTAssertEqual(try lines(of: "long-boolean-expression", in: contents, file: "p.py"), [])
    }

    // MARK: Go

    func testGoSizeRules() throws {
        let contents = """
            package main

            type Pair[K comparable, V any, W, X, Y any] struct {
            \tuserList []string
            }

            func f(a bool, b bool) bool {
            \tone, two := 1, 2
            \tuserMap := make(map[string]int)
            \tg := func() {
            \t\t_ = one
            \t}
            \tg()
            \treturn a && b || (a && !(a || b)) && one == two && len(userMap) > 0
            }
            """
        let found = try findings(contents, file: "m.go", settings: setting("too-many-locals", ["maxLocals": .int(3)]))
        XCTAssertEqual(found.filter { $0.ruleID == "too-many-generic-parameters" }.map(\.line), [3])
        XCTAssertEqual(found.filter { $0.ruleID == "too-many-locals" }.map(\.message),
                       ["Function \"f\" has 4 local variables, over the 3 limit."])
        XCTAssertEqual(found.filter { $0.ruleID == "long-boolean-expression" }.map(\.line), [14])
        XCTAssertEqual(found.filter { $0.ruleID == "type-in-name" }.map(\.line), [4, 9])
    }

    func testGoSkipsBooleanNamePrefixAndFileNameMismatch() throws {
        let contents = "package main\n\ntype Gadget struct{}\n\nvar verbose = false\n"
        let settings = setting("boolean-name-prefix")
        let found = try findings(contents, file: "widget.go", settings: settings)
        XCTAssertEqual(found.filter { ["boolean-name-prefix", "file-name-mismatch"].contains($0.ruleID) }.count, 0)
    }

    func testGoLongClosureSkipsSubtests() throws {
        let contents = """
            package main

            func TestX(t *testing.T) {
            \tt.Run("a", func(t *testing.T) {
            \t\ta()
            \t\tb()
            \t\tc()
            \t})
            \tgo func() {
            \t\ta()
            \t\tb()
            \t\tc()
            \t}()
            }
            """
        let settings = setting("long-closure", ["maxLines": .int(3)])
        XCTAssertEqual(try lines(of: "long-closure", in: contents, file: "x_test.go", settings: settings), [9])
    }
}
