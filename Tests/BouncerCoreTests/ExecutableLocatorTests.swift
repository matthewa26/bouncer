import XCTest
@testable import BouncerCore

final class ExecutableLocatorTests: XCTestCase {
    func testFindsAToolOnPath() {
        #if os(Windows)
        XCTAssertNotNil(ExecutableLocator.path(of: "cmd"))
        #else
        XCTAssertNotNil(ExecutableLocator.path(of: "sh"))
        #endif
    }

    func testReturnsNilForAToolThatIsNotOnPath() {
        XCTAssertNil(ExecutableLocator.path(of: "bouncer-no-such-tool"))
    }

    func testSearchesOnlyTheGivenPath() {
        XCTAssertNil(ExecutableLocator.path(of: "sh", environment: ["PATH": "/nonexistent"]))
    }
}
