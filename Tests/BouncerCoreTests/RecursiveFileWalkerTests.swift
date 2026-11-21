import XCTest
import Foundation
@testable import BouncerCore

final class RecursiveFileWalkerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("walker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Common"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Tool"), withIntermediateDirectories: true)
        try "let x = 1\n".write(to: root.appendingPathComponent("Common/a.swift"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func names() throws -> [String] {
        try RecursiveFileWalker(rootDirectory: root).targetFiles()
            .map { RepoPath.relative($0, to: root) }.sorted()
    }

    func testCollectsRegularFilesAndSkipsDirectories() throws {
        XCTAssertEqual(try names(), ["Common/a.swift"])
    }

    func testSkippingAFolderNeverDropsItsSiblings() throws {
        for path in ["node_modules/x.js", ".hidden/y.js", "a/b.swift", "z/c.swift", "zz/d.swift"] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "x\n".write(to: url, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(try names(), ["Common/a.swift", "a/b.swift", "z/c.swift", "zz/d.swift"])
    }

    func testSkipsSymlinksToDirectoriesAndBrokenLinksButKeepsLinksToFiles() throws {
        let manager = FileManager.default
        do {
            try manager.createSymbolicLink(at: root.appendingPathComponent("Tool/Common"), withDestinationURL: root.appendingPathComponent("Common"))
            try manager.createSymbolicLink(at: root.appendingPathComponent("Tool/b.swift"), withDestinationURL: root.appendingPathComponent("Common/a.swift"))
            try manager.createSymbolicLink(at: root.appendingPathComponent("Tool/gone.swift"), withDestinationURL: root.appendingPathComponent("missing.swift"))
        } catch {
            throw XCTSkip("Creating symlinks isn't permitted here: \(error)")
        }
        XCTAssertEqual(try names(), ["Common/a.swift", "Tool/b.swift"])
    }
}
