import XCTest
import Foundation
@testable import BouncerGit

final class GitStagedFilesProviderTests: XCTestCase {
    func testListsStagedAddedFiles() throws {
        let root = try GitFixture.makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try "let x = 1\n".write(to: root.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
        try "let y = 2\n".write(to: root.appendingPathComponent("b.swift"), atomically: true, encoding: .utf8)
        try GitFixture.run(["add", "a.swift"], in: root)

        let files = try GitStagedFilesProvider(repoRoot: root).targetFiles()
        XCTAssertEqual(files.map(\.lastPathComponent), ["a.swift"])
    }

    func testReturnsNoFilesWhenNothingIsStaged() throws {
        let root = try GitFixture.makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try "let x = 1\n".write(to: root.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)

        let files = try GitStagedFilesProvider(repoRoot: root).targetFiles()
        XCTAssertTrue(files.isEmpty)
    }

    func testExcludesStagedDeletionsViaTheDiffFilter() throws {
        let root = try GitFixture.makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let filePath = root.appendingPathComponent("a.swift")
        try "let x = 1\n".write(to: filePath, atomically: true, encoding: .utf8)
        try GitFixture.run(["add", "a.swift"], in: root)
        try GitFixture.run(["commit", "-m", "add a.swift"], in: root)
        try FileManager.default.removeItem(at: filePath)
        try GitFixture.run(["add", "a.swift"], in: root)

        let files = try GitStagedFilesProvider(repoRoot: root).targetFiles()
        XCTAssertTrue(files.isEmpty)
    }
}
