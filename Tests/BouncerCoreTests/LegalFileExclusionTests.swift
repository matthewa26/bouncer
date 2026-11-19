import XCTest
import Foundation
@testable import BouncerCore

final class LegalFileExclusionTests: XCTestCase {
    private let filter = ExcludeFilter(root: URL(fileURLWithPath: "/repo"), globs: [])

    private func excluded(_ path: String) -> Bool {
        filter.excludes(URL(fileURLWithPath: "/repo/" + path))
    }

    func testSkipsLicenseAndNoticeFilesInAnyCommonSpelling() {
        for name in ["LICENSE", "LICENSE.md", "license.txt", "LICENCE", "COPYING", "COPYING.LESSER", "NOTICE",
                     "UNLICENSE", "LICENSE-MIT", "LICENSE_APACHE", "vendor/lib/LICENSE"] {
            XCTAssertTrue(excluded(name), name)
        }
    }

    func testKeepsSourceFilesThatOnlyStartWithTheWord() {
        for name in ["license.ts", "license.py", "LicenseView.swift", "Licenses/Check.swift", "notice.go", "README.md"] {
            XCTAssertFalse(excluded(name), name)
        }
    }

    func testStillAppliesConfiguredGlobs() {
        let globbed = ExcludeFilter(root: URL(fileURLWithPath: "/repo"), globs: ["generated/**"])
        XCTAssertTrue(globbed.excludes(URL(fileURLWithPath: "/repo/generated/a.swift")))
        XCTAssertFalse(globbed.excludes(URL(fileURLWithPath: "/repo/src/a.swift")))
    }
}
