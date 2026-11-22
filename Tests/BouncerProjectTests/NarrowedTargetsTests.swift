import XCTest
import Foundation
import BouncerCore
@testable import BouncerProject

/// A narrowed target list, as `review --changed-since` produces, must not change what project rules conclude:
/// they still index every file, and only report in the targets.
final class NarrowedTargetsTests: XCTestCase {
    /// Reads `export NAME` and `import NAME from SPEC` lines as module facts.
    private struct LineFactsAnalyzer: LanguageAnalyzer {
        let supportedLanguage: Language = .typescript
        func analyze(file: SourceFile, context: AnalysisContext) throws -> [Finding] { [] }
        func moduleFacts(file: SourceFile) throws -> ModuleFacts? {
            let words = file.lines.enumerated().map { ($0.offset + 1, $0.element.split(separator: " ").map(String.init)) }
            let exports = words.filter { $0.1.first == "export" }.map { ExportFact(name: $0.1[1], line: $0.0) }
            let imports = words.filter { $0.1.first == "import" }.map { ImportFact(specifier: $0.1[3], line: $0.0, names: [$0.1[1]]) }
            return ModuleFacts(imports: imports, exports: exports)
        }
    }

    private struct Contents: FileContentsProvider {
        let files: [String: String]
        func contents(of url: URL) throws -> String { files[url.lastPathComponent] ?? "" }
    }

    private final class RecordingStore: FactsStore, @unchecked Sendable {
        var saved: [String] = []
        func cachedFacts(path: String, contentHash: String) -> FileFacts? { nil }
        func save(_ facts: [FileFacts]) throws { saved = facts.map(\.path).sorted() }
    }

    private let root = URL(fileURLWithPath: "/repo")
    private let files = [
        "util.ts": "export used\nexport unused\n",
        "app.ts": "import used from ./util\nimport loop from ./b\nexport loop2\n",
        "b.ts": "import loop2 from ./app\nexport loop\n"
    ]

    private func findings(targets: [String], index: [String], store: FactsStore = RecordingStore()) throws -> [String] {
        let urls = { (paths: [String]) in paths.map { RepoPath.url($0, in: self.root) } }
        let analyzer = LineFactsAnalyzer()
        let phase = ProjectPhase(indexProvider: ExplicitFileListProvider(files: urls(index)), store: store, analyzer: ProjectRules())
        let engine = AnalysisEngine(
            fileProvider: ExplicitFileListProvider(files: urls(targets)), contentsProvider: Contents(files: files),
            knownAnalyzers: [.typescript: analyzer], fallbackAnalyzer: analyzer,
            context: AnalysisContext(repoRoot: root, ruleSettings: [:]), project: phase
        )
        return try engine.run().findings.map { "\($0.ruleID) \(RepoPath.relative($0.filePath, to: root)):\($0.line)" }.sorted()
    }

    func testAChangedFileSeesImportsFromUnchangedFiles() throws {
        let found = try findings(targets: ["util.ts"], index: ["util.ts", "app.ts", "b.ts"])
        XCTAssertEqual(found, ["unused-export util.ts:2"], "`used` is imported by app.ts, which didn't change")
    }

    func testIndexingOnlyTheChangedFilesWouldReportFalsePositives() throws {
        let found = try findings(targets: ["util.ts"], index: ["util.ts"])
        XCTAssertEqual(found, ["unused-export util.ts:1", "unused-export util.ts:2"])
    }

    func testFindingsInUnchangedFilesAreLeftOut() throws {
        let found = try findings(targets: ["util.ts"], index: ["util.ts", "app.ts", "b.ts"])
        XCTAssertFalse(found.contains { $0.contains("app.ts") || $0.contains("b.ts") }, "the app/b cycle isn't in a target")
    }

    func testTheFactsCacheKeepsEveryIndexedFile() throws {
        let store = RecordingStore()
        _ = try findings(targets: ["util.ts"], index: ["util.ts", "app.ts", "b.ts"], store: store)
        XCTAssertEqual(store.saved, ["app.ts", "b.ts", "util.ts"])
    }
}
