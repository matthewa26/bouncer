import XCTest
import Foundation
@testable import BouncerCore

final class ProjectPhaseCloneTests: XCTestCase {
    private struct Analyzer: LanguageAnalyzer {
        let supportedLanguage: Language = .typescript
        func analyze(file: SourceFile, context: AnalysisContext) throws -> [Finding] { [] }
        func moduleFacts(file: SourceFile) throws -> ModuleFacts? { ModuleFacts(imports: []) }
    }

    /// Fingerprints every file with a recognizable marker, reporting each file's fingerprint scheme.
    private final class Fingerprinting: ProjectAnalyzer, @unchecked Sendable {
        var computed: [String] = []
        var reusedCache: [String] = []
        func findings(for facts: [FileFacts], targets: Set<String>, context: AnalysisContext) -> [Finding] {
            facts.map {
                Finding(ruleID: "project", severity: .warning, filePath: RepoPath.url($0.path, in: context.repoRoot),
                        line: 1, message: $0.clones?.scheme ?? "none")
            }
        }
        func cloneFacts(for file: SourceFile, cached: CloneFacts?, context: AnalysisContext) -> CloneFacts? {
            let path = RepoPath.relative(file.path, to: context.repoRoot)
            if let cached { reusedCache.append(path); return cached }
            computed.append(path)
            return CloneFacts(scheme: "fresh", hashes: [1], offsets: [0], lines: [0], endLines: [0], lineNumbers: [1])
        }
    }

    private final class Store: FactsStore, @unchecked Sendable {
        var cached: [String: FileFacts] = [:]
        var saved: [FileFacts] = []
        func cachedFacts(path: String, contentHash: String) -> FileFacts? {
            cached[path].flatMap { $0.contentHash == contentHash ? $0 : nil }
        }
        func save(_ facts: [FileFacts]) throws { saved = facts }
    }

    private struct Contents: FileContentsProvider {
        func contents(of url: URL) throws -> String { "export const x = 1;\n" }
    }

    private let root = URL(fileURLWithPath: "/repo")

    private func run(targets: [String], index: [String], store: Store, analyzer: Fingerprinting) throws -> [Finding] {
        let phase = ProjectPhase(
            indexProvider: ExplicitFileListProvider(files: index.map { RepoPath.url($0, in: root) }),
            store: store, analyzer: analyzer
        )
        let engine = AnalysisEngine(
            fileProvider: ExplicitFileListProvider(files: targets.map { RepoPath.url($0, in: root) }),
            contentsProvider: Contents(), knownAnalyzers: [.typescript: Analyzer()], fallbackAnalyzer: Analyzer(),
            context: AnalysisContext(repoRoot: root, ruleSettings: [:]), project: phase
        )
        return try engine.run().findings.filter { $0.ruleID == "project" }
    }

    func testTargetAndIndexedFilesBothGetFingerprintsThatAreSaved() throws {
        let store = Store(), analyzer = Fingerprinting()
        let found = try run(targets: ["a.ts"], index: ["a.ts", "b.ts"], store: store, analyzer: analyzer)
        XCTAssertEqual(found.map(\.message), ["fresh"])
        XCTAssertEqual(analyzer.computed.sorted(), ["a.ts", "b.ts"])
        XCTAssertEqual(store.saved.map { $0.clones?.scheme }, ["fresh", "fresh"])
    }

    func testCachedFingerprintsArePassedBackForUnchangedFiles() throws {
        let store = Store(), analyzer = Fingerprinting()
        let hash = StableHash.hex("export const x = 1;\n")
        let old = CloneFacts(scheme: "cached", hashes: [], offsets: [], lines: [], endLines: [], lineNumbers: [])
        for path in ["a.ts", "b.ts"] {
            store.cached[path] = FileFacts(path: path, contentHash: hash, module: ModuleFacts(imports: []), clones: old)
        }
        let found = try run(targets: ["a.ts"], index: ["a.ts", "b.ts"], store: store, analyzer: analyzer)
        XCTAssertEqual(found.map(\.message), ["cached"])
        XCTAssertEqual(analyzer.reusedCache.sorted(), ["a.ts", "b.ts"])
        XCTAssertTrue(analyzer.computed.isEmpty)
    }

    func testFileFactsWithoutFingerprintsStillDecode() throws {
        let json = #"{"path":"a.ts","contentHash":"h","module":{"imports":[],"exports":[],"references":[]}}"#
        let decoded = try JSONDecoder().decode(FileFacts.self, from: Data(json.utf8))
        XCTAssertNil(decoded.clones)
    }
}
