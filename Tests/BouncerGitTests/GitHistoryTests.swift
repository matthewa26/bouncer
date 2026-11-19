import XCTest
import BouncerCore
import Foundation
@testable import BouncerGit

/// A scratch repository whose commits have fixed authors and dates, so history tests are deterministic.
private struct DatedRepo {
    let root: URL

    init() throws {
        root = try GitFixture.makeRepo()
    }

    /// Writes files, stages everything, and commits as an author at a fixed date.
    func commit(_ files: [String: String], author: String = "dev@example.com", day: Int) throws {
        for (path, contents) in files {
            let url = path.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        try git(["add", "-A"])
        try commitStaged(author: author, day: day)
    }

    /// Commits whatever is staged.
    func commitStaged(author: String = "dev@example.com", day: Int) throws {
        let date = "2021-01-\(String(format: "%02d", day))T12:00:00Z"
        let environment = [
            "GIT_AUTHOR_NAME": "Dev", "GIT_AUTHOR_EMAIL": author, "GIT_AUTHOR_DATE": date,
            "GIT_COMMITTER_NAME": "Dev", "GIT_COMMITTER_EMAIL": author, "GIT_COMMITTER_DATE": date
        ]
        try git(["commit", "-q", "-m", "day \(day)"], environment: environment)
    }

    /// Runs git in the repository, failing on a non-zero exit.
    @discardableResult
    func git(_ arguments: [String], environment: [String: String] = [:]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try XCTUnwrap(ExecutableLocator.path(of: "git")))
        process.arguments = arguments
        process.currentDirectoryURL = root
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments.joined(separator: " ")) failed")
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

final class GitLogParserTests: XCTestCase {
    func testParsesCommitsWithTheirAuthorsDatesAndChanges() {
        let output = "\u{1E}abc\u{1F}Alice@Example.com\u{1F}1600000000\n\n3\t1\tsrc/a.ts\n-\t-\tlogo.png\n"
            + "\u{1E}def\u{1F}bob@example.com\u{1F}1500000000\n\n"
        let commits = GitLogParser.commits(from: output)
        XCTAssertEqual(commits.map(\.hash), ["abc", "def"])
        XCTAssertEqual(commits.first?.author, "alice@example.com")
        XCTAssertEqual(commits.first?.date, Date(timeIntervalSince1970: 1_600_000_000))
        XCTAssertEqual(commits.first?.changes, [
            GitFileChange(path: "src/a.ts", added: 3, deleted: 1), GitFileChange(path: "logo.png", added: nil, deleted: nil)
        ])
        XCTAssertEqual(commits.last?.changes, [])
    }

    func testSkipsRecordsAndLinesThatDontParse() {
        let output = "\u{1E}broken header\n1\t2\ta.ts\n\u{1E}ok\u{1F}a@b.c\u{1F}10\n\nnot numstat\nx\t1\tb.ts\n2\t0\tc.ts"
        let commits = GitLogParser.commits(from: output)
        XCTAssertEqual(commits.map(\.hash), ["ok"])
        XCTAssertEqual(commits.first?.changes.map(\.path), ["c.ts"])
    }

    func testParsesBothRenameForms() {
        XCTAssertEqual(GitLogParser.renamePaths("old.swift => new.swift").old, "old.swift")
        XCTAssertEqual(GitLogParser.renamePaths("old.swift => new.swift").new, "new.swift")
        let braced = GitLogParser.renamePaths("Sources/{A => B}/File.swift")
        XCTAssertEqual(braced.old, "Sources/A/File.swift")
        XCTAssertEqual(braced.new, "Sources/B/File.swift")
        let moved = GitLogParser.renamePaths("src/{ => lib}/util.ts")
        XCTAssertEqual(moved.old, "src/util.ts")
        XCTAssertEqual(moved.new, "src/lib/util.ts")
        XCTAssertEqual(GitLogParser.renamePaths("{lib => }/util.ts").new, "util.ts")
        XCTAssertNil(GitLogParser.renamePaths("plain/path.ts").old)
    }

    func testCountsChangedLinesWithBinaryFilesAsZero() {
        XCTAssertEqual(GitFileChange(path: "a", added: 3, deleted: 4).changedLines, 7)
        XCTAssertEqual(GitFileChange(path: "b", added: nil, deleted: nil).changedLines, 0)
    }

    func testFollowsRenamesSoOlderChangesUseTheCurrentPath() {
        let date = Date(timeIntervalSince1970: 0)
        let commits = [
            GitCommit(hash: "3", author: "a", date: date, changes: [GitFileChange(path: "c.ts", added: 1, deleted: 0)]),
            GitCommit(hash: "2", author: "a", date: date, changes: [
                GitFileChange(path: "c.ts", oldPath: "b.ts", added: 0, deleted: 0)
            ]),
            GitCommit(hash: "1", author: "a", date: date, changes: [GitFileChange(path: "b.ts", added: 5, deleted: 0)])
        ]
        XCTAssertEqual(RenameFollower.follow(commits).flatMap { $0.changes.map(\.path) }, ["c.ts", "c.ts", "c.ts"])
    }
}

final class GitHistoryReaderTests: XCTestCase {
    func testReadsTheWindowBeforeTheNewestCommitAcrossRenames() throws {
        let repo = try DatedRepo()
        defer { try? FileManager.default.removeItem(at: repo.root) }
        try repo.commit(["old.ts": "a\n"], day: 1)
        try repo.commit(["src/a.ts": "one\nline\nmore\nand more\n"], author: "Bob@Example.com", day: 20)
        try repo.git(["mv", "src/a.ts", "src/b.ts"])
        try repo.commitStaged(day: 25)
        try repo.commit(["src/b.ts": "changed\n"], day: 28)
        let commits = try XCTUnwrap(GitHistoryReader.commits(in: repo.root, days: 10))
        XCTAssertEqual(commits.count, 3)
        XCTAssertEqual(Set(commits.flatMap { $0.changes.map(\.path) }), ["src/b.ts"])
        XCTAssertEqual(commits.last?.author, "bob@example.com")
        XCTAssertEqual(commits.last?.changes.first?.added, 4)
    }

    func testAppliesTheMailmapToAuthors() throws {
        let repo = try DatedRepo()
        defer { try? FileManager.default.removeItem(at: repo.root) }
        try repo.commit([".mailmap": "Dev <dev@example.com> <old@example.com>\n", "a.ts": "1\n"], author: "old@example.com", day: 1)
        XCTAssertEqual(GitHistoryReader.commits(in: repo.root, days: 30)?.first?.author, "dev@example.com")
    }

    func testReturnsNilOutsideARepository() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("no-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertNil(GitHistoryReader.commits(in: directory, days: 30))
    }
}

final class GitChangeReaderTests: XCTestCase {
    func testListsStagedChangesWithLineCounts() throws {
        let repo = try DatedRepo()
        defer { try? FileManager.default.removeItem(at: repo.root) }
        try repo.commit(["a.ts": "1\n2\n"], day: 1)
        try "1\n3\n4\n".write(to: repo.root.appendingPathComponent("a.ts"), atomically: true, encoding: .utf8)
        try "new\n".write(to: repo.root.appendingPathComponent("b.ts"), atomically: true, encoding: .utf8)
        try repo.git(["add", "-A"])
        let changes = try XCTUnwrap(GitChangeReader.stagedChanges(in: repo.root))
        XCTAssertEqual(changes.sorted { $0.path < $1.path }, [
            GitFileChange(path: "a.ts", added: 2, deleted: 1), GitFileChange(path: "b.ts", added: 1, deleted: 0)
        ])
    }

    func testFindsTheMergeBaseOfTheFirstRefThatExistsAndReadsFilesThere() throws {
        let repo = try DatedRepo()
        defer { try? FileManager.default.removeItem(at: repo.root) }
        try repo.commit(["a.ts": "  indented\nbase\n"], day: 1)
        try repo.git(["branch", "trunk"])
        try repo.commit(["a.ts": "head\n"], day: 2)
        let base = try XCTUnwrap(GitChangeReader.mergeBase(of: ["no-such-ref", "trunk"], in: repo.root))
        XCTAssertEqual(base.ref, "trunk")
        XCTAssertEqual(base.commit, try repo.git(["rev-parse", "trunk"]))
        XCTAssertEqual(GitChangeReader.contents(of: "a.ts", at: base.commit, in: repo.root), "  indented\nbase\n")
        XCTAssertNil(GitChangeReader.contents(of: "missing.ts", at: base.commit, in: repo.root))
        XCTAssertNil(GitChangeReader.mergeBase(of: ["no-such-ref"], in: repo.root))
    }
}
