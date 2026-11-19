import XCTest
import Foundation
import BouncerCore
@testable import BouncerSwiftAnalyzer

final class SwiftDesignRulesTests: XCTestCase {
    private func findings(
        _ contents: String, file name: String = "a.swift", settings: [String: RuleSettings] = [:]
    ) throws -> [Finding] {
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: settings)
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/\(name)"), language: .swift, contents: contents)
        return try SwiftSyntaxAnalyzer().analyze(file: file, context: context)
    }

    private func messages(
        of ruleID: String, in contents: String, file: String = "a.swift", settings: [String: RuleSettings] = [:]
    ) throws -> [String] {
        try findings(contents, file: file, settings: settings).filter { $0.ruleID == ruleID }.map(\.message)
    }

    private func setting(_ ruleID: String, _ values: [String: RuleParameterValue] = [:]) -> [String: RuleSettings] {
        [ruleID: RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: values))]
    }

    // MARK: npath-complexity

    func testNPathMultipliesSequentialBranchesAndIsOptIn() throws {
        let contents = """
            func f(a: Bool, b: Bool, c: Bool) {
                if a { print(1) }
                if b && c { print(2) } else { print(3) }
                for x in [1] { print(x) }
                guard a else { return }
                switch a {
                case true: print(4)
                case false: print(5)
                }
            }
            """
        XCTAssertEqual(try messages(of: "npath-complexity", in: contents), [])
        XCTAssertEqual(try messages(of: "npath-complexity", in: contents, settings: setting("npath-complexity", ["max": .int(10)])),
                       ["Function \"f\" has NPath complexity 48, over the 10 limit."])
    }

    func testNPathCountsANestedFunctionAsOnePath() throws {
        let contents = """
            func f(a: Bool) {
                func g() { if a { print(1) }; if a { print(2) } }
                g()
            }
            """
        let found = try messages(of: "npath-complexity", in: contents, settings: setting("npath-complexity", ["max": .int(3)]))
        XCTAssertEqual(found, ["Function \"g\" has NPath complexity 4, over the 3 limit."])
    }

    // MARK: maintainability-index and halstead-complexity

    func testMaintainabilityIndexFlagsAHugeFunctionOnly() throws {
        let body = (1...300).map { "    let v\($0) = a * \($0) + b - \($0 % 7)" }.joined(separator: "\n")
        let contents = "func big(a: Int, b: Int) {\n\(body)\n}\nfunc small() { print(1) }\n"
        let found = try messages(of: "maintainability-index", in: contents)
        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(found.first?.hasPrefix("Function \"big\" has maintainability index ") ?? false)
        XCTAssertTrue(found.first?.hasSuffix("under the 20 minimum.") ?? false)
    }

    func testHalsteadIsOptInAndReportsAllThreeMeasures() throws {
        let contents = "func f(a: Int) -> Int {\n    let b = a + 1\n    return a * b - a / b\n}\n"
        XCTAssertEqual(try messages(of: "halstead-complexity", in: contents), [])
        let settings = setting("halstead-complexity", ["maxVolume": .int(10)])
        let found = try messages(of: "halstead-complexity", in: contents, settings: settings)
        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(found.first?.contains("Halstead volume ") ?? false)
        XCTAssertTrue(found.first?.contains("over the limits (10, 30, 30000)") ?? false)
    }

    // MARK: arrow-code

    func testArrowCodeFlagsATrailingPyramidOfIfsWithoutElse() throws {
        let contents = """
            func f(a: Int?, b: Int?) {
                guard a != 0 else { return }
                if let a {
                    if let b {
                        if a > b {
                            print(a)
                        }
                    }
                }
            }
            """
        XCTAssertEqual(try messages(of: "arrow-code", in: contents),
                       ["Function \"f\" has 3 nested ifs with no code after them (invert them into guard clauses), "
                        + "over the 2 limit."])
    }

    func testArrowCodeSkipsPyramidsWithElseOrCodeAfterThem() throws {
        let withElse = "func f(a: Bool) {\n if a { if a { if a { print(1) } } } else { print(2) }\n}\n"
        let codeAfter = "func g(a: Bool) {\n if a { if a { if a { print(1) } } }\n print(3)\n}\n"
        XCTAssertEqual(try messages(of: "arrow-code", in: withElse), [])
        XCTAssertEqual(try messages(of: "arrow-code", in: codeAfter), [])
    }

    func testArrowCodeMeasuresLoopBodies() throws {
        let contents = "func f(xs: [Int]) {\n for x in xs { if x > 0 { if x > 1 { if x > 2 { print(x) } } } }\n print(0)\n}\n"
        XCTAssertEqual(try messages(of: "arrow-code", in: contents).count, 1)
    }

    // MARK: too-many-loop-jumps

    func testLoopJumpsCountsJumpsOutOfOneLoopNotASwitch() throws {
        let contents = """
            func f(xs: [Int]) {
                outer: for x in xs {
                    if x == 1 { continue }
                    if x == 2 { break }
                    switch x {
                    case 3: break
                    default: break
                    }
                    for y in xs {
                        if y == x { continue outer }
                        if y > x { break outer }
                    }
                }
            }
            """
        XCTAssertEqual(try messages(of: "too-many-loop-jumps", in: contents, settings: setting("too-many-loop-jumps", ["maxJumps": .int(3)])),
                       ["Function \"f\" has a loop with 4 break/continue statements, over the 3 limit."])
        XCTAssertEqual(try messages(of: "too-many-loop-jumps", in: contents, settings: setting("too-many-loop-jumps", ["maxJumps": .int(4)])), [])
    }

    // MARK: recursion-without-base-case

    func testRecursionWithoutBaseCaseFlagsUnconditionalSelfCalls() throws {
        let contents = """
            func spin(_ n: Int) -> Int { spin(n + 1) }
            struct S {
                func again(times: Int) { self.again(times: times) }
            }
            """
        XCTAssertEqual(try findings(contents).filter { $0.ruleID == "recursion-without-base-case" }.map(\.line), [1, 3])
    }

    func testRecursionWithAnyBranchOverloadOrClosureIsSkipped() throws {
        let contents = """
            func fact(_ n: Int) -> Int { n <= 1 ? 1 : n * fact(n - 1) }
            func walk(_ n: Int) { guard n > 0 else { return }; walk(n - 1) }
            func load(_ x: Int) { load(Double(x)) }
            func show(_ x: Int) { show(String(x)) }
            func show(_ x: String) { print(x) }
            func later(_ n: Int) { DispatchQueue.main.async { later(n) } }
            func other(_ n: Int) { other(n, label: 1) }
            """
        XCTAssertEqual(try messages(of: "recursion-without-base-case", in: contents), [])
    }

    // MARK: weighted-methods

    func testWeightedMethodsSumsMethodComplexityAndSkipsTestSuites() throws {
        let methods = (1...4).map { "    func m\($0)(a: Bool) { if a { print(1) } else if !a { print(2) } }" }
        let contents = "struct Big {\n\(methods.joined(separator: "\n"))\n}\nfinal class BigTests {\n"
            + "\(methods.joined(separator: "\n"))\n}\n"
        XCTAssertEqual(try messages(of: "weighted-methods", in: contents, settings: setting("weighted-methods", ["max": .int(10)])),
                       ["Type \"Big\" has weighted methods (WMC) 12 across 4 methods, over the 10 limit."])
    }

    // MARK: lack-of-cohesion variants and class-cohesion

    private let splitType = """
        final class Split {
            var a = 0
            var b = 0
            func readA() -> Int { a }
            func bumpA() { a += 1 }
            func readB() -> Int { b }
            func bumpB() { b += 1 }
        }
        """

    func testLackOfCohesionVariants() throws {
        let lcom1 = setting("lack-of-cohesion", ["variant": .string("lcom1"), "maxPairs": .int(3)])
        XCTAssertEqual(try messages(of: "lack-of-cohesion", in: splitType, settings: lcom1),
                       ["Type \"Split\" has 4 method pairs sharing no field (LCOM1), over 3."])
        let lcom3 = setting("lack-of-cohesion", ["variant": .string("lcom3"), "maxGroups": .int(1)])
        XCTAssertEqual(try messages(of: "lack-of-cohesion", in: splitType, settings: lcom3),
                       ["Type \"Split\" splits into 2 unrelated method groups (LCOM3), over 1."])
        let hs = setting("lack-of-cohesion", ["variant": .string("lcom-hs"), "maxScore": .double(0.5)])
        XCTAssertEqual(try messages(of: "lack-of-cohesion", in: splitType, settings: hs),
                       ["Type \"Split\" has lack of cohesion 0.67 (LCOM-HS), over 0.5."])
        XCTAssertEqual(try messages(of: "lack-of-cohesion", in: splitType), [])
    }

    func testClassCohesionIsOptInAndReportsTCCAndLCC() throws {
        XCTAssertEqual(try messages(of: "class-cohesion", in: splitType), [])
        let settings = setting("class-cohesion", ["minTCC": .double(0.5)])
        XCTAssertEqual(try messages(of: "class-cohesion", in: splitType, settings: settings),
                       ["Type \"Split\" has tight class cohesion 33% and loose class cohesion 33% across 4 methods, "
                        + "under the minimums (TCC 50%, LCC 0%)."])
    }

    // MARK: lazy-class and middle-man

    func testLazyClassIsOptInAndSkipsDeliberatelyTinyTypes() throws {
        let contents = """
            struct Doubler { func apply(_ x: Int) -> Int { x * 2 } }
            struct Conforming: Equatable { func apply() -> Int { 1 } }
            public struct Exported { public func apply() -> Int { 1 } }
            struct Stateful { let x = 1; func apply() -> Int { x } }
            struct Extended { func apply() -> Int { 1 } }
            extension Extended: CustomStringConvertible { var description: String { "" } }
            """
        XCTAssertEqual(try messages(of: "lazy-class", in: contents), [])
        XCTAssertEqual(try messages(of: "lazy-class", in: contents, settings: setting("lazy-class")),
                       ["Type \"Doubler\" holds no state and one trivial method; make it a function, "
                        + "or fold it into its caller."])
    }

    func testMiddleManFlagsATypeThatMostlyForwards() throws {
        let contents = """
            final class Facade {
                let store = Store()
                func load() throws { try store.load() }
                func save() { self.store.save() }
                func reset() async { await store.reset() }
                func count() -> Int { store.items.count + 1 }
            }
            final class Thin {
                let store = Store()
                func load() { store.load() }
                func save() { store.persist() }
            }
            """
        XCTAssertEqual(try messages(of: "middle-man", in: contents),
                       ["Type \"Facade\" only forwards 3 of its 4 methods to \"store\"; let callers use it directly."])
    }

    // MARK: law-of-demeter

    func testLawOfDemeterIsOptInAndSkipsFluentAndDataChains() throws {
        let contents = """
            func f(order: Order, users: [User]) {
                let city = order.customer().address().region().city()
                let names = users.filter { $0.active }.map(\\.name).sorted()
                let port = config.server.http.port
                let url = base.appendingPathComponent("a").appendingPathComponent("b").appendingPathComponent("c")
                let near = order.customer().address()
            }
            """
        XCTAssertEqual(try messages(of: "law-of-demeter", in: contents), [])
        XCTAssertEqual(try findings(contents, settings: setting("law-of-demeter")).filter {
            $0.ruleID == "law-of-demeter"
        }.map(\.line), [2])
    }

    // MARK: incomplete-documentation and stale-documentation

    func testIncompleteDocumentationListsEveryMissingPart() throws {
        let contents = """
            /// Loads a thing.
            ///
            /// - Parameter path: Where.
            func load(path: String, retries: Int) throws -> Data {
                try read(path)
            }
            """
        XCTAssertEqual(try messages(of: "incomplete-documentation", in: contents),
                       ["Doc comment for \"load\" doesn't describe parameter \"retries\", the return value, "
                        + "and what it throws."])
    }

    func testIncompleteDocumentationSkipsSummariesAndNonThrowingConformances() throws {
        let contents = """
            /// Loads a thing.
            func load(path: String) -> Data { Data() }

            /// Analyzes a file.
            ///
            /// - Parameter file: The file.
            /// - Returns: The result.
            func analyze(file: String) throws -> Int { 1 }

            /// Saves.
            ///
            /// - Parameters:
            ///   - value: The value.
            func save(with value: Int) {}
            """
        XCTAssertEqual(try messages(of: "incomplete-documentation", in: contents), [])
    }

    func testStaleDocumentationFlagsNamesNotInTheSignature() throws {
        let contents = """
            /// Moves.
            ///
            /// - Parameters:
            ///   - from: The start, matching the argument label.
            ///   - distance: Renamed since.
            func move(from start: Int, by offset: Int) {}
            """
        XCTAssertEqual(try messages(of: "stale-documentation", in: contents),
                       ["Doc comment for \"move\" describes \"distance\", not in its signature."])
    }

    // MARK: oversized-test

    func testOversizedTestFlagsLongOrAssertionHeavyTestsInTestFiles() throws {
        let asserts = (1...4).map { "        XCTAssertEqual(\($0), \($0))" }.joined(separator: "\n")
        let contents = """
            final class ATests: XCTestCase {
                func testMany() {
            \(asserts)
                }
                func helperNotATest() {
            \(asserts)
                }
            }
            """
        let settings = setting("oversized-test", ["maxAssertions": .int(3)])
        XCTAssertEqual(try messages(of: "oversized-test", in: contents, file: "Tests/ATests.swift", settings: settings),
                       ["Test \"testMany\" has 4 assertions (limit 3); split it into focused tests."])
        XCTAssertEqual(try messages(of: "oversized-test", in: contents, file: "Sources/A.swift", settings: settings), [])
    }
}
