import XCTest
import BouncerCore
import Foundation
@testable import BouncerGit

/// Shared scratch-git-repo setup for BouncerGit's tests.
enum GitFixture {
    /// Creates an empty directory and runs `git init` inside it.
    ///
    /// - Returns: The new repository's root.
    static func makeRepo() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("git-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try run(["init"], in: root)
        try run(["config", "user.email", "test@example.com"], in: root)
        try run(["config", "user.name", "Test"], in: root)
        return root
    }

    /// Runs a git command in a directory, failing the test on a non-zero exit.
    ///
    /// - Parameters:
    ///   - arguments: The git subcommand and its arguments.
    ///   - directory: The working directory to run in.
    @discardableResult
    static func run(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try XCTUnwrap(ExecutableLocator.path(of: "git")))
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

final class GitRepoLocatorTests: XCTestCase {
    func testFindsTheRootOfARepoFromItsOwnDirectory() throws {
        let root = try GitFixture.makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let located = GitRepoLocator.repoRoot(startingAt: root)
        XCTAssertEqual(located?.resolvingSymlinksInPath().path, root.resolvingSymlinksInPath().path)
    }

    func testFindsTheRootFromANestedSubdirectory() throws {
        let root = try GitFixture.makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let located = GitRepoLocator.repoRoot(startingAt: nested)
        XCTAssertEqual(located?.resolvingSymlinksInPath().path, root.resolvingSymlinksInPath().path)
    }

    func testFindsTheRootWhenGivenAFileInsideTheRepo() throws {
        let root = try GitFixture.makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.swift")
        try "let x = 1\n".write(to: file, atomically: true, encoding: .utf8)
        let located = GitRepoLocator.repoRoot(startingAt: file)
        XCTAssertEqual(located?.resolvingSymlinksInPath().path, root.resolvingSymlinksInPath().path)
    }

    func testReturnsNilOutsideAnyRepo() {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-repo-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        XCTAssertNil(GitRepoLocator.repoRoot(startingAt: outside))
    }
}
