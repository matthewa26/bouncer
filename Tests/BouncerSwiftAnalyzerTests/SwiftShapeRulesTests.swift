import XCTest
import Foundation
import BouncerCore
@testable import BouncerSwiftAnalyzer

final class SwiftShapeRulesTests: XCTestCase {
    private func findings(
        _ contents: String, file name: String = "a.swift", settings: [String: RuleSettings] = [:]
    ) throws -> [Finding] {
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: settings)
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/\(name)"), language: .swift, contents: contents)
        return try SwiftSyntaxAnalyzer().analyze(file: file, context: context)
    }

    private func lines(
        of ruleID: String, in contents: String, file: String = "a.swift", settings: [String: RuleSettings] = [:]
    ) throws -> [Int] {
        try findings(contents, file: file, settings: settings).filter { $0.ruleID == ruleID }.map(\.line)
    }

    private func setting(_ ruleID: String, _ values: [String: RuleParameterValue] = [:]) -> [String: RuleSettings] {
        [ruleID: RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: values))]
    }

    // MARK: large-type

    func testLargeTypeCountsLogicalLinesOfEveryKindOfType() throws {
        let contents = """
            struct Big {
                // a comment

                let a = 1
                let b = 2
                let c = 3
            }
            enum Small { case a }
            protocol Wide {
                func a()
                func b()
                func c()
            }
            """
        let settings = setting("large-type", ["maxLines": .int(4)])
        XCTAssertEqual(try lines(of: "large-type", in: contents, settings: settings), [1, 9])
        XCTAssertEqual(try findings(contents, settings: settings).first { $0.ruleID == "large-type" }?.message,
                       "Type \"Big\" has 5 logical lines, over the 4-line limit.")
    }

    func testLargeTypeDefaultLeavesOrdinaryTypesAlone() throws {
        XCTAssertEqual(try lines(of: "large-type", in: "actor A {\n    var x = 1\n}\n"), [])
    }

    // MARK: long-closure

    func testLongClosureFlagsOnlyTheOutermostLongClosure() throws {
        let contents = """
            func f(_ xs: [Int]) {
                xs.forEach { x in
                    print(x)
                    xs.forEach { y in
                        print(y)
                        print(y)
                    }
                }
                xs.forEach { print($0) }
            }
            """
        let settings = setting("long-closure", ["maxLines": .int(3)])
        XCTAssertEqual(try lines(of: "long-closure", in: contents, settings: settings), [2])
    }

    func testLongClosureSkipsInitializersSuiteBlocksAndResultBuilders() throws {
        let contents = """
            lazy var view: Int = {
                let a = 1
                let b = 2
                return a + b
            }()
            func spec() {
                describe("a thing") {
                    print(1)
                    print(2)
                    print(3)
                }
                VStack {
                    Text("a")
                    Text("b")
                    Text("c")
                }
            }
            """
        let settings = setting("long-closure", ["maxLines": .int(3)])
        XCTAssertEqual(try lines(of: "long-closure", in: contents, settings: settings), [])
    }

    // MARK: long-boolean-expression

    func testLongBooleanExpressionCountsOperandsThroughParenthesesAndNegation() throws {
        let contents = """
            func f(a: Bool, b: Bool, c: Bool) -> Bool {
                let short = a && b || c && a
                return a && (b || !(c && a)) && b
            }
            """
        let found = try findings(contents).filter { $0.ruleID == "long-boolean-expression" }
        XCTAssertEqual(found.map(\.line), [3])
        XCTAssertEqual(found.first?.message,
                       "Long boolean expression; name its parts with local variables or a helper. (5 operands, over 4)")
    }

    func testLongBooleanExpressionSkipsEqualityOperators() throws {
        let contents = """
            struct P: Equatable {
                let a: Int, b: Int, c: Int, d: Int, e: Int
                static func == (l: P, r: P) -> Bool {
                    l.a == r.a && l.b == r.b && l.c == r.c && l.d == r.d && l.e == r.e
                }
            }
            """
        XCTAssertEqual(try lines(of: "long-boolean-expression", in: contents), [])
    }

    // MARK: too-many-locals

    func testTooManyLocalsCountsTupleNamesButNotNestedClosuresOrFunctions() throws {
        let contents = """
            func f() {
                let (a, b) = (1, 2)
                var c = 3
                let d = [1].map { value -> Int in
                    let inner = value
                    return inner
                }
                func helper() { let hidden = 1 }
                c += a + b + d.count
            }
            """
        let found = try findings(contents, settings: setting("too-many-locals", ["maxLocals": .int(3)]))
        XCTAssertEqual(found.filter { $0.ruleID == "too-many-locals" }.map(\.message),
                       ["Function \"f\" has 4 local variables, over the 3 limit."])
    }

    // MARK: too-many-generic-parameters

    func testTooManyGenericParametersOnTypesAndFunctions() throws {
        let contents = """
            struct Five<A, B, C, D, E> {}
            struct Four<A, B, C, D> {}
            func five<A, B, C, D, E>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E) {}
            """
        XCTAssertEqual(try lines(of: "too-many-generic-parameters", in: contents), [1, 3])
    }

    // MARK: long-identifier

    func testLongIdentifierFlagsVariablesFunctionsAndTypesButNotTests() throws {
        let long = String(repeating: "a", count: 51)
        let contents = """
            let \(long) = 1
            func \(long)Function() {}
            struct \(long.capitalized) {}
            func test\(long)() {}
            let fine = 1
            """
        XCTAssertEqual(try lines(of: "long-identifier", in: contents), [1, 2, 3])
    }

    // MARK: boolean-name-prefix

    func testBooleanNamePrefixIsOffUnlessConfigured() throws {
        XCTAssertEqual(try lines(of: "boolean-name-prefix", in: "var enabled = false\n"), [])
    }

    func testBooleanNamePrefixFlagsBooleansThatDoNotReadAsQuestions() throws {
        let contents = """
            var enabled = false
            var isOn: Bool = true
            var tokenIsMissing: Bool?
            var startsWithNewline = true
            let count = 1
            func f(animated: Bool) {}
            """
        let settings = setting("boolean-name-prefix")
        XCTAssertEqual(try lines(of: "boolean-name-prefix", in: contents, settings: settings), [1])
        let withParameters = setting("boolean-name-prefix", ["includeParameters": .bool(true)])
        XCTAssertEqual(try lines(of: "boolean-name-prefix", in: contents, settings: withParameters), [1, 6])
    }

    // MARK: type-in-name

    func testTypeInNameFlagsSuffixesThatMatchTheType() throws {
        let contents = """
            let userList: [String] = []
            let userDict = [String: Int]()
            let idSet = Set<Int>()
            let countInt = 3
            let playList: Int = 1
            let names: [String] = []
            let nameString = "x"
            let USER_LIST: [Int] = []
            """
        XCTAssertEqual(try lines(of: "type-in-name", in: contents), [1, 2, 3, 4])
        let withStrings = setting("type-in-name", ["suffixes": .stringList(["String"])])
        XCTAssertEqual(try lines(of: "type-in-name", in: contents, settings: withStrings), [7])
    }

    // MARK: file-name-mismatch

    func testFileNameMismatchFlagsAFileNamedForAnotherType() throws {
        XCTAssertEqual(try lines(of: "file-name-mismatch", in: "struct Gadget {}\n", file: "Widget.swift"), [1])
        let withHelper = "private struct Helper {}\nstruct Gadget {}\n"
        XCTAssertEqual(try lines(of: "file-name-mismatch", in: withHelper, file: "Widget.swift"), [2])
    }

    func testFileNameMismatchAcceptsMatchingAndConventionalNames() throws {
        let cases: [(file: String, contents: String)] = [
            ("Gadget.swift", "struct Gadget {}\nextension Gadget: Equatable {}\n"),
            ("Gadget+Codable.swift", "struct Gadget {}\n"),
            ("GadgetTests.swift", "final class GadgetTest {}\n"),
            ("Color.swift", "struct ColorOptions {}\n"),
            ("main.swift", "struct Tool {}\n"),
            ("Widget.swift", "struct Gadget {}\nstruct Gizmo {}\n"),
            ("Widget.swift", "struct Gadget {}\nfunc helper() {}\n"),
            ("Widget.swift", "struct Gadget {}\nextension String {}\n"),
            ("Widget.swift", "public struct Widget {}\nprivate struct Helper {}\n")
        ]
        for (file, contents) in cases {
            XCTAssertEqual(try lines(of: "file-name-mismatch", in: contents, file: file), [], file)
        }
    }
}
