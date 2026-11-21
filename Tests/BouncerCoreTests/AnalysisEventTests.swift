import XCTest
import Foundation
@testable import BouncerCore

final class AnalysisEventTests: XCTestCase {
    /// Collects events from the engine, which may call from any thread.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [AnalysisEvent] = []
        var events: [AnalysisEvent] { lock.lock(); defer { lock.unlock() }; return stored }
        func record(_ event: AnalysisEvent) { lock.lock(); stored.append(event); lock.unlock() }
    }

    private struct Files: TargetFileProvider {
        let files: [URL]
        func targetFiles() throws -> [URL] { files }
    }

    private struct Contents: FileContentsProvider {
        let binary: Set<URL>
        func contents(of url: URL) throws -> String {
            if binary.contains(url) { throw FileContentsError.binary(url) }
            return "let x = 1\nlet y = 2 // bouncer:disable-line fake-rule\n"
        }
    }

    /// Reports one finding per line 1 and line 2, so the suppression comment drops one per file.
    private struct TwoFindings: LanguageAnalyzer {
        let supportedLanguage: Language = .swift
        func analyze(file: SourceFile, context: AnalysisContext) throws -> [Finding] {
            [1, 2].map { Finding(ruleID: "fake-rule", severity: .warning, filePath: file.path, line: $0, message: "m") }
        }
        func moduleFacts(file: SourceFile) throws -> ModuleFacts? { ModuleFacts(imports: []) }
    }

    private struct NoProjectRules: ProjectAnalyzer {
        func findings(for facts: [FileFacts], targets: Set<String>, context: AnalysisContext) -> [Finding] { [] }
    }

    private struct NoCache: FactsStore {
        func cachedFacts(path: String, contentHash: String) -> FileFacts? { nil }
        func save(_ facts: [FileFacts]) throws {}
    }

    private let root = URL(fileURLWithPath: "/repo")

    private func engine(files: [URL], binary: Set<URL> = [], project: ProjectPhase? = nil) -> AnalysisEngine {
        AnalysisEngine(
            fileProvider: Files(files: files), contentsProvider: Contents(binary: binary),
            knownAnalyzers: [.swift: TwoFindings()], fallbackAnalyzer: TwoFindings(),
            context: AnalysisContext(repoRoot: root, ruleSettings: [:]), project: project
        )
    }

    /// Strips durations so the event sequence can be compared exactly.
    private func shape(_ event: AnalysisEvent) -> String {
        switch event {
        case let .phaseStarted(phase, total): return "start \(phase.rawValue) \(total.map(String.init) ?? "-")"
        case let .fileStarted(url): return "file \(url.lastPathComponent)"
        case let .fileFinished(url, _, count, duration):
            XCTAssertGreaterThanOrEqual(duration, .zero)
            return "done \(url.lastPathComponent) \(count)"
        case let .phaseFinished(phase, duration):
            XCTAssertGreaterThanOrEqual(duration, .zero)
            return "end \(phase.rawValue)"
        case let .note(text): return "note \(text)"
        }
    }

    func testEmitsPhasesAndFilesInOrderWithCounts() throws {
        let a = root.appendingPathComponent("a.swift")
        let b = root.appendingPathComponent("b.png")
        let recorder = Recorder()
        var engine = engine(files: [a, b], binary: [b])
        engine.onEvent = { recorder.record($0) }
        let result = try engine.run()
        XCTAssertEqual(result.findings.count, 1)
        XCTAssertEqual(recorder.events.map(shape), [
            "start discoverFiles -", "end discoverFiles",
            "start analyzeFiles 2", "file a.swift", "done a.swift 2", "file b.png", "done b.png 0",
            "note skipped 1 binary file(s)", "end analyzeFiles",
            "start baseline -", "end baseline",
            "start suppressions -", "note suppression comments switched off 1 finding(s)", "end suppressions"
        ])
    }

    func testProjectPassReportsListingIndexingAndRulesSeparately() throws {
        let a = root.appendingPathComponent("a.swift")
        let c = root.appendingPathComponent("c.swift")
        let project = ProjectPhase(indexProvider: Files(files: [a, c]), store: NoCache(), analyzer: NoProjectRules())
        let recorder = Recorder()
        var engine = engine(files: [a], project: project)
        engine.onEvent = { recorder.record($0) }
        _ = try engine.run()
        let shapes = recorder.events.map(shape)
        let start = try XCTUnwrap(shapes.firstIndex(of: "start listProjectFiles -"))
        XCTAssertEqual(Array(shapes[start...].prefix(10)), [
            "start listProjectFiles -", "end listProjectFiles",
            "start projectIndex 2", "file a.swift", "done a.swift 0", "file c.swift", "done c.swift 0",
            "note project index: 1 reused from the main pass, 0 from the facts cache, 1 parsed", "end projectIndex",
            "start projectRules -"
        ])
        XCTAssertEqual(shapes.filter { $0.hasPrefix("start") }.count, shapes.filter { $0.hasPrefix("end") }.count)
    }

    func testWithoutAHandlerTheRunIsUnchanged() throws {
        let a = root.appendingPathComponent("a.swift")
        XCTAssertEqual(try engine(files: [a]).run().findings.map(\.line), [1])
    }
}
