import XCTest
import Foundation
@testable import BouncerCore

final class ExcludeFilterTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")

    func testExcludesPathsMatchingAGlobRelativeToTheRoot() {
        let filter = ExcludeFilter(root: root, globs: ["Vendor/**", "**/*.md"])
        XCTAssertTrue(filter.excludes(URL(fileURLWithPath: "/repo/Vendor/lib/parser.c")))
        XCTAssertTrue(filter.excludes(URL(fileURLWithPath: "/repo/docs/README.md")))
        XCTAssertFalse(filter.excludes(URL(fileURLWithPath: "/repo/Sources/main.swift")))
    }

    func testExcludesNothingWithoutGlobs() {
        XCTAssertFalse(ExcludeFilter(root: root, globs: []).excludes(URL(fileURLWithPath: "/repo/a.md")))
    }

    func testExcludingProviderDropsExcludedFilesFromAnExplicitList() throws {
        let files = ["/repo/a.swift", "/repo/Vendor/b.c", "/repo/./Vendor/c.c"].map { URL(fileURLWithPath: $0) }
        let provider = ExcludingFileProvider(
            base: ExplicitFileListProvider(files: files), filter: ExcludeFilter(root: root, globs: ["Vendor/**"])
        )
        XCTAssertEqual(try provider.targetFiles().map(\.path), ["/repo/a.swift"])
    }
}
