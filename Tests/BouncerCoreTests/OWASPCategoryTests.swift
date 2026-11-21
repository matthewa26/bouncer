import XCTest
@testable import BouncerCore

final class OWASPCategoryTests: XCTestCase {
    func testEveryCategoryHasItsOwnTitle() {
        let titles = OWASPCategory.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, OWASPCategory.allCases.count)
        XCTAssertFalse(titles.contains { $0.hasPrefix("A") && $0.contains(":2025") })
    }

    func testMapsRulesToTheirCategory() {
        XCTAssertEqual(OWASPCategory.category(forRule: "sql-string-building"), .injection)
        XCTAssertEqual(OWASPCategory.category(forRule: "weak-crypto"), .cryptographicFailures)
        XCTAssertEqual(OWASPCategory.category(forRule: "unpinned-dependency"), .softwareSupplyChainFailures)
        XCTAssertNil(OWASPCategory.category(forRule: "long-function"))
    }

    func testUsesOWASPIdentifiersAsRawValues() {
        XCTAssertEqual(OWASPCategory.injection.rawValue, "A05:2025")
        XCTAssertEqual(OWASPCategory.insecureDesign.title, "Insecure Design")
    }
}
