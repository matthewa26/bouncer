import XCTest
import Foundation
@testable import BouncerCore

final class ProjectPhaseTests: XCTestCase {
    private final class CountingAnalyzer: LanguageAnalyzer, @unchecked Sendable {
        let supportedLanguage: Language = .typescript
        private let lock = NSLock()
        private var count = 0
        var parses: Int { lock.withLock { count } }
        func analyze(file: SourceFile, context: AnalysisContext) throws -> [Finding] { [] }
        func moduleFacts(file: SourceFile) throws -> ModuleFacts? {
            lock.withLock { count += 1 }
            return ModuleFacts(imports: [ImportFact(specifier: "./x", line: 1)])
        }
    }

    private struct MemoryStore: FactsStore {
        let cached: [String: FileFacts]
        func cachedFacts(path: String, contentHash: String) -> FileFacts? {
            cached[path].flatMap { $0.contentHash == contentHash ? $0 : nil }
        }
        func save(_ facts: [FileFacts]) throws {}
    }

    private struct EveryFileRule: ProjectAnalyzer {
        func findings(for facts: [FileFacts], targets: Set<String>, context: AnalysisContext) -> [Finding] {
            facts.map {
                Finding(ruleID: "project", severity: .warning, filePath: RepoPath.url($0.path, in: context.repoRoot),
                        line: 1, message: $0.module.imports.first?.specifier ?? "")
            }
        }
    }

    private struct Contents: FileContentsProvider {
        func contents(of url: URL) throws -> String { "import x from './x';\n" }
    }

    private let root = URL(fileURLWithPath: "/repo")

    private func run(targets: [String], index: [String], store: FactsStore, analyzer: CountingAnalyzer) throws -> [Finding] {
        let phase = ProjectPhase(
            indexProvider: ExplicitFileListProvider(files: index.map { RepoPath.url($0, in: root) }),
            store: store, analyzer: EveryFileRule()
        )
        let engine = AnalysisEngine(
            fileProvider: ExplicitFileListProvider(files: targets.map { RepoPath.url($0, in: root) }),
            contentsProvider: Contents(), knownAnalyzers: [.typescript: analyzer], fallbackAnalyzer: analyzer,
            context: AnalysisContext(repoRoot: root, ruleSettings: [:]), project: phase
        )
        return try engine.run().findings.filter { $0.ruleID == "project" }
    }

    func testReportsProjectFindingsOnlyInTargetFiles() throws {
        let found = try run(targets: ["a.ts"], index: ["a.ts", "b.ts"], store: MemoryStore(cached: [:]), analyzer: CountingAnalyzer())
        XCTAssertEqual(found.map { RepoPath.relative($0.filePath, to: root) }, ["a.ts"])
    }

    func testReusesCachedFactsForUnchangedNonTargetFiles() throws {
        let hash = StableHash.hex("import x from './x';\n")
        let cached = FileFacts(path: "b.ts", contentHash: hash, module: ModuleFacts(imports: [ImportFact(specifier: "./cached", line: 1)]))
        let analyzer = CountingAnalyzer()
        _ = try run(targets: ["a.ts"], index: ["a.ts", "b.ts"], store: MemoryStore(cached: ["b.ts": cached]), analyzer: analyzer)
        XCTAssertEqual(analyzer.parses, 1, "only the target is parsed; b.ts comes from the cache")
    }

    func testParsesATargetFileOnlyOnceForFindingsAndFacts() throws {
        let analyzer = CountingAnalyzer()
        let found = try run(targets: ["a.ts"], index: ["a.ts"], store: MemoryStore(cached: [:]), analyzer: analyzer)
        XCTAssertEqual(analyzer.parses, 1)
        XCTAssertEqual(found.map(\.message), ["./x"])
    }

    func testRepoPathsUseForwardSlashes() {
        XCTAssertEqual(RepoPath.relative(URL(fileURLWithPath: "/repo/src/a.ts"), to: root), "src/a.ts")
    }
}
