import XCTest
import Foundation
@testable import BouncerCore

private struct ListedFiles: TargetFileProvider {
    let files: [URL]
    func targetFiles() throws -> [URL] { files }
}

private struct InMemoryContents: FileContentsProvider {
    let contents: [URL: String]
    func contents(of url: URL) throws -> String { contents[url] ?? "" }
}

private struct SilentAnalyzer: LanguageAnalyzer {
    let supportedLanguage: Language = .other("")
    func analyze(file: SourceFile, context: AnalysisContext) throws -> [Finding] { [] }
}

/// Reports one finding at line 1 of every file it's given, and records how many files it saw.
private struct EveryFileChangeAnalyzer: ChangeAnalyzer {
    func findings(for files: [SourceFile], context: AnalysisContext) -> [Finding] {
        files.map { Finding(ruleID: "change-rule", severity: .warning, filePath: $0.path, line: 1, message: "changed") }
    }
}

final class ChangePhaseTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")

    private func engine(change: ChangeAnalyzer?, baseline: Baseline = .empty) -> AnalysisEngine {
        let file = root.appendingPathComponent("a.swift")
        return AnalysisEngine(
            fileProvider: ListedFiles(files: [file]), contentsProvider: InMemoryContents(contents: [file: "let x = 1\n"]),
            knownAnalyzers: [:], fallbackAnalyzer: SilentAnalyzer(),
            context: AnalysisContext(repoRoot: root, ruleSettings: [:]), baseline: baseline, change: change
        )
    }

    func testRunsTheChangeRulesOverTheTargetFilesWithoutAProjectPass() throws {
        let findings = try engine(change: EveryFileChangeAnalyzer()).run().findings
        XCTAssertEqual(findings.map(\.ruleID), ["change-rule"])
    }

    func testSkipsChangeRulesWhenNoneAreConfigured() throws {
        XCTAssertTrue(try engine(change: nil).run().findings.isEmpty)
    }

    func testFiltersChangeFindingsThroughTheBaseline() throws {
        let fingerprint = Baseline.fingerprint(ruleID: "change-rule", relativePath: "a.swift", lineContent: "let x = 1")
        let result = try engine(change: EveryFileChangeAnalyzer(), baseline: Baseline(fingerprints: [fingerprint])).run()
        XCTAssertTrue(result.findings.isEmpty)
    }

    func testReadsFractionalParametersAndAcceptsWholeNumbers() {
        let parameters = RuleParameters(values: ["a": .double(0.75), "b": .int(1), "c": .string("x")])
        XCTAssertEqual(parameters.double("a", default: 0), 0.75)
        XCTAssertEqual(parameters.double("b", default: 0), 1)
        XCTAssertEqual(parameters.double("c", default: 0.5), 0.5)
        XCTAssertEqual(parameters.double("missing", default: 0.9), 0.9)
    }
}
