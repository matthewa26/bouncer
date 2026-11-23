import XCTest
import Foundation
@testable import BouncerCore

final class ParallelAnalysisTests: XCTestCase {
    /// Records events, and fails if two calls ever overlap, which the engine promises they don't.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [AnalysisEvent] = []
        private var inside = false
        private(set) var overlapped = false
        var events: [AnalysisEvent] { lock.withLock { stored } }
        func record(_ event: AnalysisEvent) {
            if lock.withLock({ defer { inside = true }; return inside }) { lock.withLock { overlapped = true } }
            Thread.sleep(forTimeInterval: 0.0001)
            lock.withLock { stored.append(event); inside = false }
        }
    }

    private struct Files: TargetFileProvider {
        let files: [URL]
        func targetFiles() throws -> [URL] { files }
    }

    private struct Contents: FileContentsProvider {
        func contents(of url: URL) throws -> String {
            if url.lastPathComponent.hasPrefix("bin") { throw FileContentsError.binary(url) }
            return "line\n"
        }
    }

    /// Reports as many findings as the file's number, taking longer on some files so workers finish out of
    /// order, and fails on files named `fail`.
    private struct NumberedFindings: LanguageAnalyzer {
        let supportedLanguage: Language = .swift
        func analyze(file: SourceFile, context: AnalysisContext) throws -> [Finding] {
            let name = file.path.deletingPathExtension().lastPathComponent
            if name.hasPrefix("fail") { throw Failure(name: name) }
            let number = Int(name.dropFirst()) ?? 0
            if number % 3 == 0 { Thread.sleep(forTimeInterval: 0.002) }
            return (0..<number % 5).map {
                Finding(ruleID: "fake", severity: .warning, filePath: file.path, line: $0 + 1, message: name)
            }
        }
        func moduleFacts(file: SourceFile) throws -> ModuleFacts? { ModuleFacts(imports: []) }
    }

    private struct Failure: Error, Equatable {
        let name: String
    }

    private struct NoProjectRules: ProjectAnalyzer {
        func findings(for facts: [FileFacts], targets: Set<String>, context: AnalysisContext) -> [Finding] { [] }
    }

    private struct NoCache: FactsStore {
        func cachedFacts(path: String, contentHash: String) -> FileFacts? { nil }
        func save(_ facts: [FileFacts]) throws {}
    }

    private let root = URL(fileURLWithPath: "/repo")

    private func urls(_ names: [String]) -> [URL] {
        names.map { root.appendingPathComponent($0) }
    }

    private func engine(files: [URL], jobs: Int, index: [URL] = []) -> AnalysisEngine {
        let project = index.isEmpty
            ? nil : ProjectPhase(indexProvider: Files(files: index), store: NoCache(), analyzer: NoProjectRules())
        var engine = AnalysisEngine(
            fileProvider: Files(files: files), contentsProvider: Contents(),
            knownAnalyzers: [.swift: NumberedFindings()], fallbackAnalyzer: NumberedFindings(),
            context: AnalysisContext(repoRoot: root, ruleSettings: [:]), project: project
        )
        engine.jobs = jobs
        return engine
    }

    private var many: [URL] { urls((0..<60).map { "f\($0).swift" } + ["bin1.png", "bin2.png"]) }

    func testFindingsAndRecordsMatchASequentialRun() throws {
        let sequential = try engine(files: many, jobs: 1, index: many).runRecordingFiles()
        let parallel = try engine(files: many, jobs: 8, index: many).runRecordingFiles()
        XCTAssertEqual(parallel.result.findings, sequential.result.findings)
        XCTAssertEqual(parallel.files.map(\.loaded.path), sequential.files.map(\.loaded.path))
        XCTAssertEqual(parallel.files.map(\.findings), sequential.files.map(\.findings))
        XCTAssertEqual(parallel.files.map(\.loaded.path), (0..<60).map { "f\($0).swift" })
    }

    func testRethrowsTheEarliestFailingFilesError() {
        let files = urls((0..<40).map { $0 == 9 || $0 == 31 ? "fail\($0).swift" : "f\($0).swift" })
        for _ in 0..<10 {
            XCTAssertThrowsError(try engine(files: files, jobs: 8).run()) {
                XCTAssertEqual($0 as? Failure, Failure(name: "fail9"))
            }
        }
    }

    func testEventCountsStayCorrectAndCallsNeverOverlap() throws {
        let recorder = Recorder()
        var engine = engine(files: many, jobs: 8, index: many)
        engine.onEvent = { recorder.record($0) }
        _ = try engine.run()
        XCTAssertFalse(recorder.overlapped)
        for phase in [AnalysisPhase.analyzeFiles, .projectIndex] {
            let events = try self.events(of: phase, in: recorder.events)
            XCTAssertEqual(events.filter { if case .fileStarted = $0 { true } else { false } }.count, many.count)
            XCTAssertEqual(events.filter { if case .fileFinished = $0 { true } else { false } }.count, many.count)
        }
        XCTAssertTrue(recorder.events.contains(.note("skipped 2 binary file(s)")))
    }

    func testJobsBelowOneAreTreatedAsOne() {
        XCTAssertEqual(engine(files: [], jobs: 0).jobs, 1)
        XCTAssertEqual(engine(files: [], jobs: -3).jobs, 1)
        XCTAssertGreaterThanOrEqual(AnalysisEngine.defaultJobs, 1)
    }

    /// The events between a phase's start and finish.
    private func events(of phase: AnalysisPhase, in events: [AnalysisEvent]) throws -> ArraySlice<AnalysisEvent> {
        let start = try XCTUnwrap(events.firstIndex { if case .phaseStarted(phase, _) = $0 { true } else { false } })
        let end = try XCTUnwrap(events.firstIndex { if case .phaseFinished(phase, _) = $0 { true } else { false } })
        return events[start...end]
    }
}
