import XCTest
import Foundation
import BouncerCore
import BouncerConfig
import BouncerHeuristicAnalyzer
import BouncerSwiftAnalyzer
@testable import BouncerProject

/// Runs the real Swift and heuristic analyzers, with the project pass, over a multi-file tree at one job and
/// at eight, and expects the same findings and records in the same order.
final class ParallelRealAnalysisTests: XCTestCase {
    private var root: URL!

    private let shared = (1...12).map { "    let value\($0) = compute(\($0)) + offset * \($0)" }.joined(separator: "\n")

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("parallel-\(UUID().uuidString)")
        for index in 0..<40 {
            let body = index % 4 == 0 ? shared : "    return x! + \(index * 37)"
            try write("Sources/M\(index % 3)/File\(index).swift", "import M\((index + 1) % 3)\n"
                + "func f\(index)(x: Int?) -> Int {\n\(body)\n    fatalError(\"no\")\n}\n")
        }
        for index in 0..<6 {
            try write("scripts/tool\(index).py", "import os\n\ndef run\(index)(a, b, c, d, e, f):\n    return 9999\n")
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ path: String, _ text: String) throws {
        let url = RepoPath.url(path, in: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func engine(jobs: Int, prior: PriorRun? = nil) -> AnalysisEngine {
        let walker = RecursiveFileWalker(rootDirectory: root)
        var engine = AnalysisEngine(
            fileProvider: walker, contentsProvider: FileSystemContentsProvider(),
            knownAnalyzers: [.swift: SwiftSyntaxAnalyzer()], fallbackAnalyzer: HeuristicAnalyzer(language: .other("")),
            context: AnalysisContext(repoRoot: root, ruleSettings: [:]),
            project: ProjectPhase(indexProvider: walker, store: JSONFactsStore(repoRoot: root), analyzer: ProjectRules())
        )
        engine.jobs = jobs
        engine.priorRun = prior
        return engine
    }

    /// Clears the facts cache, so each run parses every file afresh.
    private func clearCache() {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(".bouncer-cache"))
    }

    func testOneJobAndEightJobsFindTheSameThingsInTheSameOrder() throws {
        clearCache()
        let sequential = try engine(jobs: 1).runRecordingFiles()
        clearCache()
        let parallel = try engine(jobs: 8).runRecordingFiles()
        XCTAssertFalse(sequential.result.findings.isEmpty)
        XCTAssertTrue(sequential.result.findings.contains { $0.ruleID == "import-cycle" }, "the project pass ran")
        XCTAssertEqual(parallel.result.findings, sequential.result.findings)
        XCTAssertEqual(parallel.otherFindings, sequential.otherFindings)
        XCTAssertEqual(parallel.files.map(\.loaded.path), sequential.files.map(\.loaded.path))
        XCTAssertEqual(parallel.files.map(\.findings), sequential.files.map(\.findings))
        XCTAssertEqual(parallel.files.map(\.hidden), sequential.files.map(\.hidden))
        XCTAssertEqual(parallel.files.map(\.loaded.contentHash), sequential.files.map(\.loaded.contentHash))
    }

    func testAParallelRunFromASavedRunMatchesASequentialOne() throws {
        let session = SavedRunSession(
            store: JSONSavedRunStore(repoRoot: root),
            key: SavedRun.Key(version: "test", config: BouncerConfig.empty, root: root), mode: .incremental
        )
        session.save(try engine(jobs: 8).runRecordingFiles(), repoRoot: root) { _ in }
        try write("Sources/M0/File0.swift", "func changed(y: Int?) -> Int { y! }\n")
        let fromSaved = try engine(jobs: 8, prior: session.prior()).runRecordingFiles()
        let fresh = try engine(jobs: 1).runRecordingFiles()
        XCTAssertEqual(fromSaved.result.findings, fresh.result.findings)
    }

    func testTheSavedRunKeyIgnoresJobs() throws {
        var threaded = BouncerConfig.empty
        threaded.jobs = 4
        let plain = SavedRun.Key(version: "test", config: BouncerConfig.empty.findingSettings, root: root)
        XCTAssertEqual(SavedRun.Key(version: "test", config: threaded.findingSettings, root: root), plain)
        XCTAssertNotEqual(SavedRun.Key(version: "test", config: threaded, root: root), plain)
    }
}
