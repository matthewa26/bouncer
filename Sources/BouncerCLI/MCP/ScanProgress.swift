import Foundation
import BouncerCore
import BouncerReporting

/// A running scan's progress, updated from its analysis events, possibly on worker threads, and read by tool calls.
///
/// It's unchecked because `lock` guards every mutable property: the engine calls its event handler
/// synchronously, one at a time, from analysis threads, so an actor would need a task per event.
final class ScanProgress: @unchecked Sendable {
    /// Guards every stored property below.
    private let lock = NSLock()
    /// When the scan started.
    private let start = ContinuousClock.now
    /// Where the scan's notes go.
    private let log: MCPLog
    /// The step the scan is in.
    private var phase: AnalysisPhase?
    /// How many files the main pass will analyze, once known.
    private var total: Int?
    /// How many it has analyzed.
    private var done = 0
    /// The saved run's note: how many files were reused, or why none were.
    private var savedRunNote: String?

    /// Creates the progress of a scan starting now.
    ///
    /// - Parameter log: Where the scan's notes go.
    init(log: MCPLog) {
        self.log = log
    }

    /// Records one analysis event.
    ///
    /// - Parameter event: The event.
    func record(_ event: AnalysisEvent) {
        lock.lock()
        defer { lock.unlock() }
        switch event {
        case .phaseStarted(let started, let count): began(started, total: count)
        case .fileFinished where phase == .analyzeFiles: done += 1
        case .note(let note): noted(note)
        default: break
        }
    }

    /// Notes the step the scan entered, and the main pass's file count.
    ///
    /// - Parameters:
    ///   - started: The step.
    ///   - count: How many files it goes through, if known.
    private func began(_ started: AnalysisPhase, total count: Int?) {
        phase = started
        if started == .analyzeFiles { total = count }
    }

    /// Keeps the saved run's note and logs every note.
    ///
    /// - Parameter note: The note.
    private func noted(_ note: String) {
        if note.hasPrefix("saved run") { savedRunNote = note }
        log.write(note)
    }

    /// How long the scan has run.
    var elapsed: Duration { ContinuousClock.now - start }

    /// The saved run's note, once the scan has made it.
    var reuseNote: String? {
        lock.lock()
        defer { lock.unlock() }
        return savedRunNote
    }

    /// Describes the scan's progress.
    ///
    /// - Returns: A line such as `Scanning: 42% (120 of 284 files), 3s elapsed. Call status.`
    func line() -> String {
        lock.lock()
        defer { lock.unlock() }
        let step = phase.map { "\(Self.describe($0))" }
        let seconds = Int(elapsed.components.seconds)
        return AgentSessionText.progress(done: done, total: total, elapsedSeconds: seconds, step: step)
    }

    /// Names a step for the progress line.
    ///
    /// - Parameter phase: The step.
    /// - Returns: Words such as `running project rules`.
    private static func describe(_ phase: AnalysisPhase) -> String {
        switch phase {
        case .listProjectFiles, .projectIndex: "indexing the project"
        case .projectRules: "running project rules"
        case .changeRules: "running change rules"
        case .coverage: "reading coverage"
        default: "finishing up"
        }
    }
}
