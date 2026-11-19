import XCTest
import Foundation
import BouncerCore
@testable import BouncerSwiftAnalyzer

final class SwiftDesignFactsTests: XCTestCase {
    private func structure(_ contents: String) throws -> StructureFacts {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/Sources/A/a.swift"), language: .swift, contents: contents)
        return try XCTUnwrap(SwiftSyntaxAnalyzer().moduleFacts(file: file)).structure
    }

    func testRecordsRequirementsStubsOverridesAndPreconditions() throws {
        let contents = """
            protocol Exporter { func export(report: String) throws -> Data; func preview() -> String }
            struct Fax: Exporter {
                func export(report: String) throws -> Data { throw ExportError.unsupportedFormat }
                func preview() -> String { fatalError("not supported") }
                func reset() {}
                func save() throws { throw ExportError.diskFull }
            }
            class Pricer {
                func price(quantity: Int) -> Int {
                    precondition(quantity > 0)
                    return quantity
                }
                func discount(code: String) -> Int {
                    guard enabled else { fatalError() }
                    return 1
                }
                func cap(limit: Int) throws -> Int {
                    guard limit < 10 else { throw Failure.tooBig }
                    return limit
                }
            }
            class Wholesale: Pricer { override func price(quantity: Int) -> Int { 1 } }
            extension Fax: CustomStringConvertible { func describe() {} }
            """
        let facts = try structure(contents)
        let exporter = facts.types[0], fax = facts.types[1], pricer = facts.types[2], wholesale = facts.types[3]
        XCTAssertEqual(exporter.methods, ["export", "preview"])
        XCTAssertEqual(fax.methods, ["export", "preview", "reset", "save"])
        XCTAssertEqual(fax.refusedOwn, ["export", "preview"])
        XCTAssertEqual(fax.emptyOwn, ["reset"])
        XCTAssertEqual(fax.refused + fax.empty, [])
        XCTAssertEqual(pricer.guarded, ["price", "cap"])
        XCTAssertEqual(wholesale.overrides, ["price"])
        XCTAssertEqual(facts.types[4].kind, .extension)
        XCTAssertEqual(facts.types[4].emptyOwn, ["describe"])
    }

    func testRecordsMethodOwnersAndReturnTypes() throws {
        let facts = try structure("""
            struct A { func f(x: Int) -> [String: Int] { [:] } }
            extension A { func g() {} }
            func free(y: String) -> Bool { true }
            """)
        XCTAssertEqual(facts.functions.map { "\($0.owner ?? "-").\($0.name)->\($0.returns ?? "-")" },
                       ["A.f->[String:Int]", "A.g->-", "-.free->Bool"])
    }

    func testRecordsTypedReadsAndKeptConstructions() throws {
        let contents = """
            final class Checkout {
                private let gateway = StripeGateway()
                private var store: Store
                private let log: Logger
                init(clock: Clock) {
                    store = Store()
                    self.log = Logger()
                    let temp = Formatter()
                    _ = temp.style
                }
                func buy(order: Order, other: Order?) -> Int {
                    let local: Cart = Cart()
                    var shadow: Order = order
                    if let other { _ = other.tax }
                    _ = shadow.count
                    return order.total + local.items + self.gateway.fee + clock.now + String().count
                }
                func later(order: Invoice) -> Int { order.total }
            }
            """
        let facts = try structure(contents)
        let checkout = try XCTUnwrap(facts.collaborations.first)
        XCTAssertEqual(checkout.owner, "Checkout")
        XCTAssertEqual(checkout.line, 1)
        XCTAssertEqual(checkout.constructs, ["Logger", "Store", "StripeGateway"])
        XCTAssertEqual(checkout.uses, ["Cart.items", "Clock.now", "Formatter.style", "Order.count", "Order.tax",
                                       "StripeGateway.fee"])
    }
}
