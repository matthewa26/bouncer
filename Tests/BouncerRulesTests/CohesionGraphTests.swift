import XCTest
@testable import BouncerRules

final class CohesionGraphTests: XCTestCase {
    private func method(_ name: String, _ references: Set<String>) -> CohesionGraph.Method {
        CohesionGraph.Method(name: name, references: references)
    }

    func testMethodsSharingAFieldFormOneGroup() {
        XCTAssertEqual(CohesionGraph.groupCount([method("a", ["count"]), method("b", ["count"])]), 1)
    }

    func testMethodsWithDisjointFieldsFormSeparateGroups() {
        let methods = [method("load", ["cache"]), method("save", ["cache"]), method("render", ["view"])]
        XCTAssertEqual(CohesionGraph.groupCount(methods), 2)
    }

    func testACallConnectsTwoMethods() {
        XCTAssertEqual(CohesionGraph.groupCount([method("a", ["b"]), method("b", ["x"])]), 1)
    }

    func testConnectionsAreTransitive() {
        let methods = [method("a", ["x"]), method("b", ["x", "y"]), method("c", ["y"])]
        XCTAssertEqual(CohesionGraph.groupCount(methods), 1)
    }

    func testFewerThanTwoMethodsIsCohesive() {
        XCTAssertEqual(CohesionGraph.groupCount([]), 1)
        XCTAssertEqual(CohesionGraph.groupCount([method("a", [])]), 1)
    }
}
