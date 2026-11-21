import XCTest
import Foundation
@testable import BouncerCore

/// A file list whose files only let one rule report.
private struct ScopedProvider: TargetFileProvider {
    let files: [URL]
    func targetFiles() throws -> [URL] { files }
    func ruleScope(for url: URL) -> Set<String>? { ["kept-rule"] }
}

/// An analyzer reporting one finding from each of two rules.
private struct TwoRuleAnalyzer: LanguageAnalyzer {
    let supportedLanguage = Language.other("yml")
    func analyze(file: SourceFile, context: AnalysisContext) throws -> [Finding] {
        ["kept-rule", "dropped-rule"].map { Finding(ruleID: $0, severity: .warning, filePath: file.path, line: 1, message: "m") }
    }
}

final class HiddenCIFilesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ci-walk-\(UUID().uuidString)")
        for path in [".github/workflows/ci.yml", ".github/actions/setup/action.yaml", ".github/dependabot.yml",
                     ".github/CODEOWNERS", ".hidden/x.yml", ".env", "src/a.yml"] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "x: 1\n".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testWalksOnlyTheWorkflowsAndActionsInsideHiddenFolders() throws {
        let names = try RecursiveFileWalker(rootDirectory: root).targetFiles().map { RepoPath.relative($0, to: root) }
        XCTAssertEqual(names.sorted(), [".github/actions/setup/action.yaml", ".github/workflows/ci.yml", "src/a.yml"])
    }

    func testLimitsWalkedCIFilesToTheSupplyChainRules() {
        let walker = RecursiveFileWalker(rootDirectory: root)
        XCTAssertEqual(walker.ruleScope(for: root.appendingPathComponent(".github/workflows/ci.yml")), HiddenCIFiles.ruleIDs)
        XCTAssertNil(walker.ruleScope(for: root.appendingPathComponent("src/a.yml")))
    }

    func testWalkingTheGithubFolderItselfKeepsEveryFileAndRule() throws {
        let github = root.appendingPathComponent(".github")
        let walker = RecursiveFileWalker(rootDirectory: github)
        XCTAssertEqual(try walker.targetFiles().count, 4)
        XCTAssertNil(walker.ruleScope(for: github.appendingPathComponent("workflows/ci.yml")))
    }

    func testOtherProvidersLeaveEveryRuleOn() {
        XCTAssertNil(ExplicitFileListProvider(files: []).ruleScope(for: root))
    }

    func testTheEngineDropsFindingsFromRulesOutsideAFilesScope() throws {
        let file = root.appendingPathComponent(".github/workflows/ci.yml")
        let engine = AnalysisEngine(
            fileProvider: ScopedProvider(files: [file]), contentsProvider: FileSystemContentsProvider(),
            knownAnalyzers: [:], fallbackAnalyzer: TwoRuleAnalyzer(),
            context: AnalysisContext(repoRoot: root, ruleSettings: [:])
        )
        XCTAssertEqual(try engine.run().findings.map(\.ruleID), ["kept-rule"])
    }
}
