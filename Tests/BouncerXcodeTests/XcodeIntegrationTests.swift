import XCTest
@testable import BouncerXcode

final class XcodeIntegrationTests: XCTestCase {
    func testIsSupportedOnlyOnMacOS() {
        #if os(macOS)
        XCTAssertTrue(XcodeIntegration.isSupported)
        #else
        XCTAssertFalse(XcodeIntegration.isSupported)
        #endif
    }
}
