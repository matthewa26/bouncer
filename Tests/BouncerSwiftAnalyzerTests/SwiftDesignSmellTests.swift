import XCTest
import Foundation
import BouncerCore
@testable import BouncerSwiftAnalyzer

final class SwiftDesignSmellTests: XCTestCase {
    private func messages(
        of ruleID: String, in contents: String, file: String = "a.swift", settings: [String: RuleSettings] = [:]
    ) throws -> [String] {
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: settings)
        let source = SourceFile(path: URL(fileURLWithPath: "/repo/\(file)"), language: .swift, contents: contents)
        return try SwiftSyntaxAnalyzer().analyze(file: source, context: context)
            .filter { $0.ruleID == ruleID }.map(\.message)
    }

    private func setting(_ ruleID: String, _ values: [String: RuleParameterValue] = [:]) -> [String: RuleSettings] {
        [ruleID: RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: values))]
    }

    // MARK: coupling-between-objects

    func testCouplingCountsNamedTypesButNotLibraryNestedOrGenericOnes() throws {
        let contents = """
            final class Checkout<Item> {
                struct Line { let total: Double }
                var cart: Cart
                var payments: [Payment] = []
                func run(item: Item, line: Line) -> Receipt {
                    let tax = TaxTable.shared.rate
                    return Receipt(total: Double(tax), currency: Currency.usd, lines: [String]())
                }
            }
            """
        XCTAssertEqual(try messages(of: "coupling-between-objects", in: contents), [])
        XCTAssertEqual(
            try messages(of: "coupling-between-objects", in: contents, settings: setting("coupling-between-objects", ["max": .int(4)])),
            ["Type \"Checkout\" is coupled to 5 other types (CBO), over the 4 limit."]
        )
    }

    // MARK: response-for-class

    func testResponseForClassAddsDistinctCalleesToMethods() throws {
        let contents = """
            struct Report {
                init() { setUp() }
                func a() { print(1); helper.run(); b() }
                func b() { print(2); log() }
            }
            """
        let settings = setting("response-for-class", ["max": .int(5)])
        XCTAssertEqual(try messages(of: "response-for-class", in: contents), [])
        XCTAssertEqual(try messages(of: "response-for-class", in: contents, settings: settings),
                       ["Type \"Report\" has response for a class (RFC) 7: 3 methods plus 4 distinct methods they call, "
                        + "over the 5 limit."])
    }

    // MARK: god-class formula

    func testLanzaMarinescuFormulaNeedsComplexityForeignDataAndLowCohesion() throws {
        let branches = (1...12).map { "if v > \($0) { v += 1 }" }.joined(separator: "; ")
        let methods = (1...4).map { "func m\($0)(o: Order) -> Int { var v = o.a\($0) + o.b\($0); \(branches); return v + f\($0) }" }
        let contents = "final class Hub {\n" + (1...4).map { "    var f\($0) = 0" }.joined(separator: "\n")
            + "\n" + methods.map { "    " + $0 }.joined(separator: "\n") + "\n}\n"
        let formula = setting("god-class", ["formula": .string("lanza-marinescu")])
        XCTAssertEqual(try messages(of: "god-class", in: contents, settings: formula), [
            "Type \"Hub\" is a god class by the Lanza–Marinescu formula: WMC 52 (at least 47), ATFD 8 (at least 6), "
                + "and TCC 0.0% (under 33.3%)."
        ])
        let strict = setting("god-class", ["formula": .string("lanza-marinescu"), "minATFD": .int(9)])
        XCTAssertEqual(try messages(of: "god-class", in: contents, settings: strict), [])
        XCTAssertEqual(try messages(of: "god-class", in: contents), [])
    }

    // MARK: feature-envy

    func testFeatureEnvyFlagsAMethodReadingAnotherObjectMoreThanItself() throws {
        let contents = """
            final class Printer {
                private var header = ""
                func summary(order: Order) -> String {
                    let net = order.total - order.discount + order.shipping
                    return header + order.customer + "\\(order.items) \\(net)"
                }
                func copy(order: Order) -> Receipt {
                    Receipt(total: order.total, discount: order.discount, shipping: order.shipping, items: order.items, customer: order.customer)
                }
                func configure(process: Process) {
                    process.a = 1; process.b = 2; process.c = 3; process.d = 4; process.e = 5
                }
                func toText(order: Order) -> String { "\\(order.total)\\(order.discount)\\(order.shipping)\\(order.items)\\(order.customer)" }
                static func make(order: Order) -> String { "\\(order.total)\\(order.discount)\\(order.shipping)\\(order.items)\\(order.customer)" }
            }
            """
        let settings = setting("feature-envy")
        XCTAssertEqual(try messages(of: "feature-envy", in: contents), [])
        XCTAssertEqual(try messages(of: "feature-envy", in: contents, settings: settings), [
            "Method \"summary\" uses 5 members of \"order\" but 1 of its own type (feature envy); move it to "
                + "\"order\"'s type."
        ])
        XCTAssertEqual(try messages(of: "feature-envy", in: contents, file: "Tests/PrinterTests.swift", settings: settings), [])
    }

    // MARK: temporary-field

    func testTemporaryFieldFlagsAPrivateFieldOnlyOneMethodSetsThenReads() throws {
        let contents = """
            final class Parser {
                private var tokens: [String] = []
                private var scratch: [String]?
                private var cache: [String]?
                private var shared: Int?
                var visible: Int?
                func words() -> Int {
                    scratch = tokens.filter { !$0.isEmpty }
                    visible = 1
                    _ = visible
                    return scratch?.count ?? 0
                }
                func cached() -> [String] {
                    if let cache { return cache }
                    cache = tokens
                    return tokens
                }
                func a() { shared = 1; print(shared ?? 0) }
                func b() { print(shared ?? 0) }
            }
            """
        XCTAssertEqual(try messages(of: "temporary-field", in: contents), [
            "Field \"scratch\" of \"Parser\" is set and read only inside \"words\" (temporary field); "
                + "make it a local variable there."
        ])
        let extended = contents + "\nextension Parser { func more() {} }\n"
        XCTAssertEqual(try messages(of: "temporary-field", in: extended), [])
    }

    // MARK: command-query-separation

    func testCommandQuerySeparationSkipsFluentCachingNamedAndMutatingMethods() throws {
        let contents = """
            final class Cursor {
                private var index = 0
                private var cache: [Int]?
                func reset(to position: Int) -> Bool { index = position; return index > 0 }
                func next() -> Int { index += 1; return index }
                func rewound() -> Cursor { index = 0; return self }
                @discardableResult func clear() -> Int { index = 0; return 0 }
                func values() -> [Int] { if cache == nil { cache = [index] }; return cache ?? [] }
                func peek() -> Int { index }
                func mark(_ node: Int) -> Status { index = node; if node > 1 { return .skip }; return .visit }
                override func description() -> String { index = 2; return "" }
            }
            struct Counter {
                var n = 0
                mutating func bump() -> Int { n += 1; return n }
            }
            """
        XCTAssertEqual(try messages(of: "command-query-separation", in: contents), [])
        XCTAssertEqual(try messages(of: "command-query-separation", in: contents, settings: setting("command-query-separation")), [
            "Method \"reset\" both changes \"index\" and returns a value (command–query separation); "
                + "split it into a command and a query."
        ])
    }

    // MARK: tell-dont-ask

    func testTellDontAskFlagsChangingTheStateAnIfAskedAbout() throws {
        let contents = """
            func withdraw(_ amount: Double, from account: Account) {
                if account.balance >= amount { account.balance -= amount }
                if account.isOpen { account.setBalance(0) }
                if account.isFrozen { ledger.balance = 0 }
                if account.items.count > 0 { account.items.count = 0 }
                var local = Account()
                if local.balance > 0 { local.balance = 0 }
            }
            """
        XCTAssertEqual(try messages(of: "tell-dont-ask", in: contents), [])
        let found = try messages(of: "tell-dont-ask", in: contents, settings: setting("tell-dont-ask"))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.hasPrefix("Checks another object's state, then changes it"), true)
    }

    // MARK: primitive-obsession

    func testPrimitiveObsessionCountsRequiredPrimitivesAndStringlyNames() throws {
        let contents = """
            struct Bank {
                var accountId: String
                var id: String
                func transfer(fromId: String, toId: String, amount: Double, currency: String) {}
                func open(customerEmail: String, limit: Int, file: StaticString = #file, line: UInt = #line) {}
                init(a: String, b: String, c: Int, d: Double) { accountId = a; id = b }
                func label(name: String, count: Int) {}
            }
            """
        XCTAssertEqual(try messages(of: "primitive-obsession", in: contents), [])
        XCTAssertEqual(try messages(of: "primitive-obsession", in: contents, settings: setting("primitive-obsession")), [
            "Function \"transfer\" takes 4 string or number parameters (primitive obsession); group related ones into a type.",
            "Function \"open\" takes \"customerEmail\": String as plain primitives (primitive obsession); give it a domain type.",
            "Field \"accountId\" is a plain String (primitive obsession); give it a domain type."
        ])
    }
}
