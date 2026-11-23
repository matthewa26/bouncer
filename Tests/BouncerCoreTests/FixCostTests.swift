import XCTest
@testable import BouncerCore

final class FixCostTests: XCTestCase {
    func testTagsRulesWithTheirCost() {
        XCTAssertEqual(FixCost.cost(forRule: "force-unwrap"), .mechanical)
        XCTAssertEqual(FixCost.cost(forRule: "missing-documentation"), .mechanical)
        XCTAssertEqual(FixCost.cost(forRule: "weak-crypto"), .mechanical)
        XCTAssertEqual(FixCost.cost(forRule: "duplicate-block"), .refactor)
        XCTAssertEqual(FixCost.cost(forRule: "god-class"), .refactor)
        XCTAssertEqual(FixCost.cost(forRule: "coverage-threshold"), .refactor)
        XCTAssertNil(FixCost.cost(forRule: "no-such-rule"))
    }

    func testNoRuleIsTaggedTwice() {
        let listed = FixCost.table.flatMap(\.rules)
        let repeated = Dictionary(grouping: listed) { $0 }.filter { $0.value.count > 1 }.keys.sorted()
        XCTAssertEqual(repeated, [], "Tagged more than once: \(repeated.joined(separator: ", "))")
        XCTAssertEqual(FixCost.taggedRuleIDs.count, listed.count)
    }

    func testEachCostListsItsRulesSorted() {
        for row in FixCost.table {
            XCTAssertEqual(row.rules, row.rules.sorted(), "\(row.cost) rules aren't sorted")
        }
        XCTAssertEqual(FixCost.table.map(\.cost), FixCost.allCases)
    }

    func testSummariesDiffer() {
        XCTAssertEqual(FixCost.mechanical.summary, "a local fix")
        XCTAssertEqual(FixCost.refactor.summary, "needs restructuring")
    }

    func testUncataloguedRulesAreTagged() {
        for id in FixCost.uncataloguedRuleIDs {
            XCTAssertNotNil(FixCost.cost(forRule: id), id)
        }
    }
}
