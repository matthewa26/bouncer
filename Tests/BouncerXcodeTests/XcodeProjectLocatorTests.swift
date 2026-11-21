import XCTest
import Foundation
@testable import BouncerXcode

final class XcodeProjectLocatorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("xcode-locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func addProject(_ name: String) throws {
        try FileManager.default.createDirectory(at: directory.appendingPathComponent(name), withIntermediateDirectories: true)
    }

    func testFindsTheOnlyProject() throws {
        try addProject("App.xcodeproj")
        try addProject("Other.xcworkspace")
        XCTAssertEqual(try XcodeProjectLocator.locate(explicitPath: nil, in: directory).lastPathComponent, "App.xcodeproj")
    }

    func testNoProjectIsAnError() {
        XCTAssertThrowsError(try XcodeProjectLocator.locate(explicitPath: nil, in: directory)) {
            XCTAssertEqual($0 as? XcodeIntegrationError, .noProject(directory: self.directory.path))
        }
    }

    func testSeveralProjectsAreListed() throws {
        try addProject("B.xcodeproj")
        try addProject("A.xcodeproj")
        XCTAssertThrowsError(try XcodeProjectLocator.locate(explicitPath: nil, in: directory)) {
            XCTAssertEqual($0 as? XcodeIntegrationError, .severalProjects(["A.xcodeproj", "B.xcodeproj"]))
            XCTAssertTrue("\($0)".contains("A.xcodeproj, B.xcodeproj"))
        }
    }

    func testExplicitPathIsResolvedAgainstTheDirectory() throws {
        let url = try XcodeProjectLocator.locate(explicitPath: "Sub/../App.xcodeproj", in: directory)
        XCTAssertEqual(url.path, directory.appendingPathComponent("App.xcodeproj").standardizedFileURL.path)
    }
}
