import XCTest
import Foundation
@testable import BouncerCore

final class FileContentsProviderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("contents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ name: String, _ bytes: [UInt8]) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    func testRejectsAFileWithANulByteAsBinary() throws {
        let url = try write("pic.png", [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00])
        XCTAssertThrowsError(try FileSystemContentsProvider().contents(of: url)) { error in
            XCTAssertEqual(error as? FileContentsError, .binary(url))
        }
    }

    func testReadsNonUTF8TextWithReplacementCharacters() throws {
        let url = try write("latin1.py", Array("x = 'caf".utf8) + [0xE9] + Array("'\n".utf8))
        XCTAssertEqual(try FileSystemContentsProvider().contents(of: url), "x = 'caf\u{FFFD}'\n")
    }

    func testEngineSkipsBinaryFilesInsteadOfFailing() throws {
        let text = try write("a.swift", Array("let x = 1\n".utf8))
        let binary = try write("b.png", [0x00, 0x01])
        let engine = AnalysisEngine(
            fileProvider: ExplicitFileListProvider(files: [text, binary]),
            contentsProvider: FileSystemContentsProvider(), knownAnalyzers: [:], fallbackAnalyzer: NoFindings(),
            context: AnalysisContext(repoRoot: directory, ruleSettings: [:])
        )
        XCTAssertEqual(try engine.run().findings.count, 1)
    }

    private struct NoFindings: LanguageAnalyzer {
        let supportedLanguage = Language.swift
        func analyze(file: SourceFile, context: AnalysisContext) throws -> [Finding] {
            [Finding(ruleID: "seen", severity: .warning, filePath: file.path, line: 1, message: file.path.lastPathComponent)]
        }
    }
}
