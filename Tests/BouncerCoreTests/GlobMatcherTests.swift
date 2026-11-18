import XCTest
@testable import BouncerCore

final class GlobMatcherTests: XCTestCase {
    func testStarMatchesWithinOneDirectoryLevel() {
        XCTAssertTrue(GlobMatcher.matches(path: "README.md", pattern: "*.md"))
        XCTAssertFalse(GlobMatcher.matches(path: "docs/README.md", pattern: "*.md"))
    }

    func testDoubleStarSlashMatchesNestedFiles() {
        XCTAssertTrue(GlobMatcher.matches(path: "docs/Articles/Hooks.md", pattern: "**/*.md"))
        XCTAssertTrue(GlobMatcher.matches(path: "a/b/c/Hooks.md", pattern: "**/*.md"))
    }

    func testDoubleStarSlashAlsoMatchesRootLevelFiles() {
        XCTAssertTrue(GlobMatcher.matches(path: "README.md", pattern: "**/*.md"))
    }

    func testDoubleStarSlashMatchesEveryFileUnderADirectory() {
        XCTAssertTrue(GlobMatcher.matches(path: "Tests/BouncerCoreTests/GlobMatcherTests.swift", pattern: "Tests/**"))
        XCTAssertFalse(GlobMatcher.matches(path: "Sources/BouncerCore/GlobMatcher.swift", pattern: "Tests/**"))
    }

    func testQuestionMarkMatchesExactlyOneCharacter() {
        XCTAssertTrue(GlobMatcher.matches(path: "a.swift", pattern: "?.swift"))
        XCTAssertFalse(GlobMatcher.matches(path: "ab.swift", pattern: "?.swift"))
    }
}
