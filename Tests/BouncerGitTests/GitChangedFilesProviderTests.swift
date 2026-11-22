import XCTest
import Foundation
import BouncerCore
@testable import BouncerGit

final class GitChangedFilesProviderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = try GitFixture.makeRepo()
        try write("kept.swift")
        try write("edited.swift")
        try write("staged.swift")
        try write("committed.swift")
        try write("deleted.swift")
        try write("old name.swift")
        try write("sub/inner.swift")
        try write(".gitignore", "ignored.swift\n")
        try commitAll("base")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ path: String, _ contents: String = "let x = 1\n", in base: URL? = nil) throws {
        let url = (base ?? root).appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func commitAll(_ message: String) throws {
        try GitFixture.run(["add", "-A"], in: root)
        try GitFixture.run(["commit", "-m", message], in: root)
    }

    private func changed(since revision: String = "HEAD", under directory: URL? = nil, exclude: [String] = []) throws -> [String] {
        let base = directory ?? root!
        let provider = try GitChangedFilesProvider(revision: revision, rootDirectory: base, excludeGlobs: exclude)
        return try provider.targetFiles().map { RepoPath.relative($0, to: base) }
    }

    func testListsCommittedStagedUnstagedAndUntrackedChanges() throws {
        try write("committed.swift", "let y = 2\n")
        try commitAll("change")
        try write("staged.swift", "let y = 2\n")
        try GitFixture.run(["add", "staged.swift"], in: root)
        try write("edited.swift", "let y = 2\n")
        try write("new file.swift")
        XCTAssertEqual(try changed(since: "HEAD~1"), ["committed.swift", "edited.swift", "new file.swift", "staged.swift"])
    }

    func testLeavesOutIgnoredAndDeletedFiles() throws {
        try write("ignored.swift")
        try FileManager.default.removeItem(at: root.appendingPathComponent("deleted.swift"))
        try GitFixture.run(["rm", "--cached", "-q", "deleted.swift"], in: root)
        XCTAssertEqual(try changed(), [])
    }

    func testListsARenamedFileUnderItsNewPath() throws {
        try GitFixture.run(["mv", "old name.swift", "new name.swift"], in: root)
        try commitAll("rename")
        XCTAssertEqual(try changed(since: "HEAD~1"), ["new name.swift"])
    }

    func testKeepsUnicodePathsIntact() throws {
        try write("café/naïve file.swift")
        XCTAssertEqual(try changed(), ["café/naïve file.swift"])
    }

    func testScopesToTheReviewedSubdirectory() throws {
        try write("sub/inner.swift", "let y = 2\n")
        try write("sub/extra.swift")
        try write("edited.swift", "let y = 2\n")
        XCTAssertEqual(try changed(under: root.appendingPathComponent("sub")), ["extra.swift", "inner.swift"])
    }

    func testAppliesTheWalkersSkippedHiddenAndExcludedRules() throws {
        try write("node_modules/pkg/index.js")
        try write(".hidden/secret.swift")
        try write(".env", "TOKEN=1\n")
        try write("Generated/out.swift")
        try write(".github/workflows/ci.yml", "on: push\n")
        try write(".github/README.md", "notes\n")
        XCTAssertEqual(try changed(exclude: ["Generated/**"]), [".github/workflows/ci.yml"])
    }

    func testScopesRulesInCIFilesLikeTheWalker() throws {
        try write(".github/workflows/ci.yml", "on: push\n")
        let provider = try GitChangedFilesProvider(revision: "HEAD", rootDirectory: root)
        let file = try XCTUnwrap(provider.targetFiles().first)
        XCTAssertNotNil(provider.ruleScope(for: file))
    }

    func testRejectsAnUnknownRevision() {
        XCTAssertThrowsError(try changed(since: "no-such-branch")) {
            XCTAssertEqual($0 as? GitError, .unknownRevision("no-such-branch"))
        }
    }

    func testRejectsARevisionThatLooksLikeAnOption() {
        XCTAssertThrowsError(try changed(since: "--output=x")) {
            XCTAssertEqual($0 as? GitError, .unknownRevision("--output=x"))
        }
    }

    func testRejectsADirectoryOutsideARepository() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        XCTAssertThrowsError(try changed(under: outside)) {
            guard case .notARepository = $0 as? GitError else { return XCTFail("unexpected error \($0)") }
        }
    }
}
