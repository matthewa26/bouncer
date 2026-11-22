import XCTest
import Foundation
import BouncerCore
import BouncerConfig
import BouncerHeuristicAnalyzer
import BouncerSwiftAnalyzer
@testable import BouncerProject

/// Collects a run's log notes from the engine's `@Sendable` event handler.
private final class NoteLog: @unchecked Sendable {
    private let lock = NSLock()
    private var notes: [String] = []

    var handler: AnalysisEventHandler {
        { [self] event in
            guard case let .note(text) = event else { return }
            lock.lock()
            notes.append(text)
            lock.unlock()
        }
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return notes
    }
}

final class SavedRunTests: XCTestCase {
    private var root: URL!

    /// Lib.swift has per-file findings (force unwrap, fatalError) and shares a long block with Other.swift, so
    /// the project pass reports duplicate code across them.
    private let shared = (1...12).map { "    let value\($0) = compute(\($0)) + offset * \($0)" }.joined(separator: "\n")

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("saved-run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write("Sources/App/Lib.swift", "func lib(x: Int?) -> Int {\n\(shared)\n    fatalError(\"no\")\n    return x!\n}\n")
        try write("Sources/App/Other.swift", "func other() {\n\(shared)\n}\n")
        try write("Sources/App/Gone.swift", "func gone(y: Int?) -> Int { y! }\n")
        try write("Sources/Tool/Run.swift", "func run(z: Int?) { print(z!) }\n")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Helpers

    private func write(_ path: String, _ text: String) throws {
        let url = RepoPath.url(path, in: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func remove(_ path: String) throws {
        try FileManager.default.removeItem(at: RepoPath.url(path, in: root))
    }

    private func config(_ json: String = #"{"rules": {"swift-fatal-error": {"params": {"libraryOnly": true}}}}"#)
        throws -> BouncerConfig {
        try JSONDecoder().decode(BouncerConfig.self, from: Data(json.utf8))
    }

    private func engine(config: BouncerConfig, baseline: Baseline = .empty, prior: PriorRun? = nil,
                        log: NoteLog? = nil) -> AnalysisEngine {
        let walker = RecursiveFileWalker(rootDirectory: root)
        var engine = AnalysisEngine(
            fileProvider: walker, contentsProvider: FileSystemContentsProvider(),
            knownAnalyzers: [.swift: SwiftSyntaxAnalyzer()], fallbackAnalyzer: HeuristicAnalyzer(language: .other("")),
            context: AnalysisContext(repoRoot: root, ruleSettings: config.resolvedRuleSettings()), baseline: baseline,
            project: ProjectPhase(indexProvider: walker, store: JSONFactsStore(repoRoot: root), analyzer: ProjectRules())
        )
        engine.priorRun = prior
        if let log { engine.onEvent = log.handler }
        return engine
    }

    private func key(_ config: BouncerConfig, version: String = "test") -> SavedRun.Key {
        SavedRun.Key(version: version, config: config, root: root)
    }

    private func session(_ config: BouncerConfig, mode: SavedRunMode = .incremental, version: String = "test")
        -> SavedRunSession {
        SavedRunSession(store: JSONSavedRunStore(repoRoot: root), key: key(config, version: version), mode: mode)
    }

    /// Runs like `review` with a saved-run session: start from the saved run, then save this one.
    @discardableResult
    private func review(_ config: BouncerConfig, session: SavedRunSession, baseline: Baseline = .empty,
                        log: NoteLog = NoteLog()) throws -> AnalysisResult {
        let run = engine(config: config, baseline: baseline, prior: session.prior(), log: log)
        let recorded = try run.runRecordingFiles()
        session.save(recorded, repoRoot: root, emit: log.handler)
        return recorded.result
    }

    /// Findings as sorted lines, since a full run's order among same-line findings isn't fixed.
    private func lines(_ result: AnalysisResult) -> [String] {
        result.findings.map {
            "\(RepoPath.relative($0.filePath, to: root)):\($0.line) \($0.ruleID) \($0.severity) \($0.message)"
        }.sorted()
    }

    private func reuseNote(_ log: NoteLog) -> String? {
        log.all.first { $0.hasPrefix("saved run") }
    }

    // MARK: - Format

    func testSavedRunRoundTripsThroughTheCompactFormat() throws {
        let finding = SavedRun.SavedFinding(ruleID: "force-unwrap", severity: .warning, line: 3, message: "Unwrap.")
        let error = SavedRun.SavedFinding(ruleID: "long-function", severity: .error, line: 9, message: "Too long.")
        let run = SavedRun(
            key: SavedRun.Key(version: "1.2.0", config: "abc", root: "/repo"),
            files: [
                SavedRun.File(path: "a.swift", stamp: FileStamp(size: 10, modified: 1_700_000_000_123_456_789),
                              contentHash: "0123456789abcdef", findings: [finding, error, finding], hidden: [1],
                              affectsNeighbors: false),
                SavedRun.File(path: "Sources/main.swift", stamp: nil, contentHash: nil, findings: [], hidden: [],
                              affectsNeighbors: true)
            ],
            otherFindings: [SavedRun.PlacedFinding(path: "b.swift", finding: error)]
        )
        let store = JSONSavedRunStore(repoRoot: root)
        try store.save(run)
        XCTAssertEqual(try store.load(), run)
        XCTAssertEqual(run.reportedCount, 3)
    }

    func testSavedFindingsTakeWellUnderOneHundredBytesEach() throws {
        let files = (0..<100).map { index in
            SavedRun.File(
                path: "Sources/Module\(index % 7)/File\(index).swift", stamp: FileStamp(size: 4_096, modified: 1),
                contentHash: "0123456789abcdef",
                findings: (1...200).map { line in
                    SavedRun.SavedFinding(ruleID: ["force-unwrap", "magic-number", "long-lines"][line % 3],
                                          severity: .warning, line: line, message: "Magic number; name it with a constant.")
                },
                hidden: [], affectsNeighbors: false
            )
        }
        let run = SavedRun(key: SavedRun.Key(version: "1", config: "c", root: "/r"), files: files, otherFindings: [])
        let bytes = try JSONSavedRunStore(repoRoot: root).save(run)
        XCTAssertLessThan(Double(bytes) / Double(run.reportedCount), 30)
    }

    func testACorruptSavedRunFailsToLoad() throws {
        let store = JSONSavedRunStore(repoRoot: root)
        try write(".bouncer-cache/last-run.json", "{ not json")
        XCTAssertThrowsError(try store.load())
        let badIndex = #"{"format":1,"key":{"version":"v","config":"c","root":"/r"},"severities":["error"],"#
            + #""rules":[],"messages":[],"paths":["a.swift"],"files":[{"path":0,"findings":[1,5,0,0]}],"other":[]}"#
        try write(".bouncer-cache/last-run.json", badIndex)
        XCTAssertThrowsError(try store.load()) { XCTAssertTrue($0 is SavedRunError) }
    }

    // MARK: - Invalidation

    func testACorruptSavedRunFallsBackToAFullRunAndSaysSo() throws {
        let config = try config()
        let full = try review(config, session: session(config))
        try write(".bouncer-cache/last-run.json", "garbage")
        let log = NoteLog()
        let fallback = try review(config, session: session(config), log: log)
        XCTAssertEqual(lines(fallback), lines(full))
        XCTAssertTrue(reuseNote(log)?.contains("can't be read") == true, "\(log.all)")
        XCTAssertNotNil(try JSONSavedRunStore(repoRoot: root).load(), "the fallback run saves a fresh copy")
    }

    func testAConfigChangeInvalidatesTheSavedRun() throws {
        try review(try config(), session: session(try config()))
        let changed = try config(#"{"rules": {"force-unwrap": {"enabled": false}}}"#)
        let log = NoteLog()
        let result = try review(changed, session: session(changed), log: log)
        XCTAssertTrue(reuseNote(log)?.contains("the config changed") == true, "\(log.all)")
        XCTAssertFalse(result.findings.contains { $0.ruleID == "force-unwrap" })
    }

    func testAVersionChangeInvalidatesTheSavedRun() throws {
        let config = try config()
        try review(config, session: session(config, version: "1.2.0"))
        let log = NoteLog()
        try review(config, session: session(config, version: "1.3.0"), log: log)
        XCTAssertTrue(reuseNote(log)?.contains("another Bouncer build") == true, "\(log.all)")
    }

    func testKeysDifferOnlyWhenTheirInputsDo() throws {
        let config = try config()
        XCTAssertNil(key(config).mismatch(with: key(config)))
        XCTAssertNotNil(key(config).mismatch(with: key(.empty)))
        let elsewhere = SavedRun.Key(version: "test", config: config, root: root.appendingPathComponent("Sources"))
        XCTAssertNotNil(key(config).mismatch(with: elsewhere))
    }

    // MARK: - Incremental runs

    func testAnUnchangedRepoReusesEveryFile() throws {
        let config = try config()
        let full = try review(config, session: session(config))
        let log = NoteLog()
        let again = try review(config, session: session(config), log: log)
        XCTAssertEqual(lines(again), lines(full))
        XCTAssertTrue(reuseNote(log)?.hasPrefix("saved run: reused findings for 4 of 4 file(s)") == true, "\(log.all)")
    }

    func testIncrementalRunEqualsAFullRunAfterEditsAdditionsAndDeletions() throws {
        let config = try config()
        try review(config, session: session(config))
        try write("Sources/App/Lib.swift", "func lib(x: Int?) -> Int {\n\(shared)\n    return x! + x!\n}\n")
        try write("Sources/App/New.swift", "func new(w: Int?) -> Int {\n\(shared)\n    return w!\n}\n")
        try remove("Sources/App/Gone.swift")
        let log = NoteLog()
        let incremental = try review(config, session: session(config), log: log)
        let full = try engine(config: config).run()
        XCTAssertEqual(lines(incremental), lines(full))
        XCTAssertTrue(lines(full).contains { $0.hasPrefix("Sources/App/New.swift") })
        XCTAssertFalse(lines(incremental).contains { $0.hasPrefix("Sources/App/Gone.swift") })
        let note = try XCTUnwrap(reuseNote(log))
        XCTAssertTrue(note.contains("reused findings for 2 of 4") && note.contains("1 changed, 1 new"), note)
        XCTAssertTrue(note.contains("dropped 1 deleted"), note)
    }

    func testAnEditThatKeepsTheSizeAndModificationTimeIsStillCaught() throws {
        let config = try config()
        try review(config, session: session(config))
        let url = RepoPath.url("Sources/Tool/Run.swift", in: root)
        let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]
        try write("Sources/Tool/Run.swift", "func run(q: Int?) { print(q?.description ?? \"\") }\n")
        try FileManager.default.setAttributes([.modificationDate: modified as Any], ofItemAtPath: url.path)
        let incremental = try review(config, session: session(config))
        XCTAssertEqual(lines(incremental), lines(try engine(config: config).run()))
        XCTAssertFalse(lines(incremental).contains { $0.hasPrefix("Sources/Tool/Run.swift") && $0.contains("force") })
    }

    func testANewEntryPointReanalyzesTheFilesBelowIt() throws {
        let config = try config()
        let before = try review(config, session: session(config))
        XCTAssertTrue(lines(before).contains { $0.contains("Lib.swift") && $0.contains("swift-fatal-error") })
        try write("Sources/App/main.swift", "lib(x: 1)\n")
        let log = NoteLog()
        let incremental = try review(config, session: session(config), log: log)
        XCTAssertEqual(lines(incremental), lines(try engine(config: config).run()))
        XCTAssertFalse(lines(incremental).contains { $0.contains("Lib.swift") && $0.contains("swift-fatal-error") })
        XCTAssertTrue(reuseNote(log)?.contains("near a changed manifest") == true, "\(log.all)")
    }

    func testTheBaselineAndSuppressionsApplyToReusedFindings() throws {
        let config = try config()
        try review(config, session: session(config))
        let line = "func run(z: Int?) { print(z!) }"
        let unwrap = try XCTUnwrap(try engine(config: config).run().findings.first {
            $0.filePath.lastPathComponent == "Run.swift" && $0.ruleID == "force-unwrap"
        })
        let baseline = Baseline(fingerprints: [
            Baseline.fingerprint(ruleID: unwrap.ruleID, relativePath: "Sources/Tool/Run.swift", lineContent: line)
        ])
        let log = NoteLog()
        let incremental = try review(config, session: session(config), baseline: baseline, log: log)
        XCTAssertEqual(lines(incremental), lines(try engine(config: config, baseline: baseline).run()))
        XCTAssertFalse(incremental.findings.contains { $0.filePath.lastPathComponent == "Run.swift" && $0.ruleID == "force-unwrap" })
        XCTAssertTrue(reuseNote(log)?.contains("reused findings for 4 of 4") == true, "\(log.all)")
    }

    func testTheSavedRunRecordsWhichFindingsWereHidden() throws {
        let config = try config()
        try write("Sources/Tool/Run.swift", "func run(z: Int?) { print(z!) } // bouncer:disable-line force-unwrap\n")
        let result = try review(config, session: session(config))
        let saved = try XCTUnwrap(try JSONSavedRunStore(repoRoot: root).load())
        let run = try XCTUnwrap(saved.files.first { $0.path == "Sources/Tool/Run.swift" })
        XCTAssertEqual(run.hidden.map { run.findings[$0].ruleID }, ["force-unwrap"])
        XCTAssertEqual(saved.reportedCount, result.findings.count)
        XCTAssertNotNil(run.stamp)
    }

    // MARK: - Modes

    func testReadOnlyModeReusesTheSavedRunButWritesNothing() throws {
        let config = try config()
        try review(config, session: session(config))
        let store = JSONSavedRunStore(repoRoot: root)
        let before = try Data(contentsOf: store.location)
        try write("Sources/Tool/Run.swift", "func run() {}\n")
        let log = NoteLog()
        try review(config, session: session(config, mode: .readOnly), log: log)
        XCTAssertEqual(try Data(contentsOf: store.location), before)
        XCTAssertTrue(reuseNote(log)?.contains("reused findings for 3 of 4") == true, "\(log.all)")
    }

    func testFullModeIgnoresTheSavedRunButRefreshesIt() throws {
        let config = try config()
        try review(config, session: session(config))
        try write("Sources/Tool/Run.swift", "func run() {}\n")
        let log = NoteLog()
        try review(config, session: session(config, mode: .full), log: log)
        XCTAssertNil(reuseNote(log))
        let saved = try XCTUnwrap(try JSONSavedRunStore(repoRoot: root).load())
        XCTAssertEqual(saved.files.first { $0.path == "Sources/Tool/Run.swift" }?.findings, [])
    }

    func testAPlainRunWritesNoSavedRun() throws {
        _ = try engine(config: try config()).run()
        XCTAssertFalse(FileManager.default.fileExists(atPath: JSONSavedRunStore(repoRoot: root).location.path))
    }
}

// MARK: - Neighbor files

final class NeighborFilesTests: XCTestCase {
    func testManifestsAndEntryPointsAffectTheirNeighbors() {
        XCTAssertTrue(NeighborFiles.affectsNeighbors(path: "Package.swift", contents: ""))
        XCTAssertTrue(NeighborFiles.affectsNeighbors(path: "crates/a/Cargo.toml", contents: ""))
        XCTAssertTrue(NeighborFiles.affectsNeighbors(path: "Sources/Tool/Entry.swift", contents: "@main struct T {}"))
        XCTAssertFalse(NeighborFiles.affectsNeighbors(path: "Sources/Tool/Util.swift", contents: "func f() {}"))
        XCTAssertFalse(NeighborFiles.affectsNeighbors(path: "README.md", contents: "@main"))
    }

    func testAFileIsUnderItsAncestorDirectoriesOnly() {
        XCTAssertTrue(NeighborFiles.isUnder("Sources/App/Lib.swift", anyOf: ["Sources"]))
        XCTAssertTrue(NeighborFiles.isUnder("Sources/App/Lib.swift", anyOf: [""]))
        XCTAssertFalse(NeighborFiles.isUnder("Sources/AppKit/Lib.swift", anyOf: ["Sources/App"]))
        XCTAssertEqual(NeighborFiles.directory(of: "Package.swift"), "")
    }
}
