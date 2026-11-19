import XCTest
@testable import BouncerRules

final class DesignMetricsTests: XCTestCase {
    private func method(_ name: String, _ references: Set<String>) -> CohesionGraph.Method {
        CohesionGraph.Method(name: name, references: references)
    }

    // MARK: LCOM variants and TCC/LCC

    func testLCOM1And2CountPairsSharingNoField() {
        let methods = [method("a", ["x"]), method("b", ["x"]), method("c", ["y"])]
        XCTAssertEqual(CohesionGraph.lcom1(methods, fields: ["x", "y"]), 2)
        XCTAssertEqual(CohesionGraph.lcom2(methods, fields: ["x", "y"]), 1)
        XCTAssertEqual(CohesionGraph.lcom2([method("a", ["x"]), method("b", ["x"])], fields: ["x"]), 0)
    }

    func testLCOM3IgnoresCallsBetweenMethods() {
        let methods = [method("a", ["x", "b"]), method("b", ["y"])]
        XCTAssertEqual(CohesionGraph.lcom3(methods, fields: ["x", "y"]), 2)
        XCTAssertEqual(CohesionGraph.groupCount(methods), 1)
    }

    func testHendersonSellersRunsFromSharedToPrivateFields() {
        let shared = [method("a", ["x", "y"]), method("b", ["x", "y"])]
        let separate = [method("a", ["x"]), method("b", ["y"])]
        XCTAssertEqual(CohesionGraph.hendersonSellers(shared, fields: ["x", "y"]), 0)
        XCTAssertEqual(CohesionGraph.hendersonSellers(separate, fields: ["x", "y", "unused"]), 1)
        XCTAssertEqual(CohesionGraph.hendersonSellers([method("a", ["x"])], fields: ["x"]), 0)
    }

    func testClassCohesionFollowsCallsAndSkipsStatelessMethods() throws {
        let methods = [
            method("a", ["x"]), method("b", ["x", "helper"]), method("helper", ["y"]), method("c", ["y"]),
            method("d", ["z"]), method("pure", [])
        ]
        let ratios = try XCTUnwrap(CohesionGraph.classCohesion(methods, fields: ["x", "y", "z"]))
        XCTAssertEqual(ratios.methods, 5)
        XCTAssertEqual(ratios.tight, 4.0 / 10.0, accuracy: 0.001)
        XCTAssertEqual(ratios.loose, 6.0 / 10.0, accuracy: 0.001)
        XCTAssertNil(CohesionGraph.classCohesion([method("a", ["x"]), method("b", [])], fields: ["x"]))
    }

    func testWeightedMethodsSumsComplexities() {
        let structure = TypeStructure(methods: [], fieldNames: [], methodComplexities: [1, 3, 5], isPlain: true)
        XCTAssertEqual(structure.weightedMethods, 9)
    }

    // MARK: Halstead and NPath

    func testHalsteadMeasures() {
        let counts = HalsteadCounts.tally(operators: ["=", "+", "="], operands: ["a", "b", "a", "1"])
        XCTAssertEqual(counts, HalsteadCounts(distinctOperators: 2, distinctOperands: 3, totalOperators: 3,
                                              totalOperands: 4))
        XCTAssertEqual(counts.volume, 7 * log2(5), accuracy: 0.001)
        XCTAssertEqual(counts.difficulty, 1 * 4.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(counts.effort, counts.difficulty * counts.volume, accuracy: 0.001)
        XCTAssertEqual(HalsteadCounts().volume, 0)
    }

    func testPathCountSaturates() {
        XCTAssertEqual(PathCount.multiply(PathCount.cap, 2), PathCount.cap)
        XCTAssertEqual(PathCount.multiply(Int.max, Int.max), PathCount.cap)
        XCTAssertEqual(PathCount.add(PathCount.cap, 1), PathCount.cap)
        XCTAssertEqual(PathCount.multiply(3, 4), 12)
    }

    // MARK: Law of Demeter

    private func segments(_ spec: String) -> [DemeterChain.Segment] {
        spec.split(separator: ".").map { part in
            DemeterChain.Segment(name: part.replacingOccurrences(of: "()", with: ""), isCall: part.hasSuffix("()"))
        }
    }

    func testDemeterReachCountsStepsPastTheFirstObject() {
        XCTAssertEqual(DemeterChain.reach(base: "order", segments: segments("customer().address().city()")), 2)
        XCTAssertEqual(DemeterChain.reach(base: "self", segments: segments("store.cart.owner.profile().avatar()")), 3)
    }

    func testDemeterSkipsDataPathsFluentCallsTypesAndLiterals() {
        XCTAssertEqual(DemeterChain.reach(base: "config", segments: segments("server.http.port")), 0)
        XCTAssertEqual(DemeterChain.reach(base: "users", segments: segments("filter().map().first()")), 0)
        XCTAssertEqual(DemeterChain.reach(base: "builder", segments: segments("withName().setAge().build()")), 0)
        XCTAssertEqual(DemeterChain.reach(base: "UIApplication", segments: segments("shared.delegate().window()")), 0)
        XCTAssertEqual(DemeterChain.reach(base: nil, segments: segments("a().b().c()")), 0)
        XCTAssertEqual(DemeterChain.reach(base: "pkg", segments: segments("models.User().save()")), 0)
    }

    func testDemeterDropsTrailingAccessorsAndCanTreatUppercaseAsMembers() {
        XCTAssertEqual(DemeterChain.reach(base: "a", segments: segments("b().c().d().count")), 2)
        let goChain = segments("Elem().Kind().String()")
        XCTAssertEqual(DemeterChain.reach(base: "v", segments: goChain, uppercaseIsType: false), 2)
        XCTAssertEqual(DemeterChain.reach(base: "v", segments: goChain), 0)
    }
}
