import Foundation

/// One step of a run, in the order a full run goes through them.
///
/// The engine reports the steps from `discoverFiles` to `suppressions`; the command line wraps them in the
/// hook and reporting steps, so a progress display can show every stage with one vocabulary.
public enum AnalysisPhase: String, Sendable, CaseIterable {
    /// Running the `preCheck` hooks.
    case preCheckHooks
    /// Listing the files to analyze.
    case discoverFiles
    /// Reading and analyzing each target file.
    case analyzeFiles
    /// Dropping findings the baseline already accepts.
    case baseline
    /// Parsing the coverage report.
    case coverage
    /// Listing the files the project pass indexes, which can be the whole repo.
    case listProjectFiles
    /// Gathering every project file's module facts, from the main pass, the cache, or a fresh parse.
    case projectIndex
    /// Running the project rules over the indexed facts.
    case projectRules
    /// Running the change rules over the diff being checked.
    case changeRules
    /// Dropping findings a `bouncer:disable…` comment switches off.
    case suppressions
    /// Rendering the report.
    case report
    /// Running the `postCheck` hooks.
    case postCheckHooks

    /// Runs a step between its `phaseStarted` and `phaseFinished` events, timing it on a monotonic clock.
    ///
    /// - Parameters:
    ///   - total: How many files the step will go through, if it's known up front.
    ///   - emit: Receives the events.
    ///   - body: The step itself.
    /// - Returns: What `body` returns.
    /// - Throws: Whatever `body` throws, in which case no `phaseFinished` event is sent.
    public func run<T>(total: Int? = nil, emit: AnalysisEventHandler, _ body: () throws -> T) rethrows -> T {
        emit(.phaseStarted(self, total: total))
        let start = ContinuousClock.now
        let value = try body()
        emit(.phaseFinished(self, duration: ContinuousClock.now - start))
        return value
    }
}

/// Something that happened during a run, for progress displays and logs.
///
/// Events arrive one at a time, never overlapping, and in step order: each `phaseStarted` is followed by any
/// file events and notes for that step and then its `phaseFinished`, unless the step throws. With
/// `AnalysisEngine.jobs` above one, a step that goes through files in parallel (`analyzeFiles`, `projectIndex`)
/// reports them from its worker threads, so different files' `fileStarted` and `fileFinished` events
/// interleave; every file still gets one of each, and its `fileFinished` follows its `fileStarted`.
public enum AnalysisEvent: Sendable, Equatable {
    /// A step began, with the number of files it will go through when that's known.
    case phaseStarted(AnalysisPhase, total: Int?)
    /// A file is about to be read and analyzed (or indexed, during `projectIndex`).
    case fileStarted(URL)
    /// A file is done: its language, how many findings it produced, and how long it took.
    case fileFinished(URL, language: Language, findingCount: Int, duration: Duration)
    /// A step ended, with how long it took.
    case phaseFinished(AnalysisPhase, duration: Duration)
    /// A detail worth logging, such as how many findings the baseline accepted.
    case note(String)
}

/// Receives a run's events.
///
/// The engine never calls a handler from two threads at once, but it may call it from a thread other than the
/// one that started the run; see `AnalysisEvent`.
public typealias AnalysisEventHandler = @Sendable (AnalysisEvent) -> Void

extension AnalysisEvent {
    /// Wraps a handler so that calls from several threads take turns rather than overlap.
    ///
    /// - Parameter handler: The handler.
    /// - Returns: A handler that passes each event on while holding a lock.
    static func serialized(_ handler: @escaping AnalysisEventHandler) -> AnalysisEventHandler {
        let lock = NSLock()
        return { event in lock.withLock { handler(event) } }
    }
}

extension AnalysisEvent {
    /// Times one file's work between its `fileStarted` and `fileFinished` events.
    ///
    /// - Parameters:
    ///   - url: The file.
    ///   - emit: Receives the events.
    ///   - body: The work, returning how many findings it produced.
    /// - Returns: What `body` returns.
    /// - Throws: Whatever `body` throws, in which case no `fileFinished` event is sent.
    static func timingFile<T>(
        _ url: URL, emit: AnalysisEventHandler, _ body: () throws -> (value: T, findings: Int)
    ) rethrows -> T {
        emit(.fileStarted(url))
        let start = ContinuousClock.now
        let (value, findings) = try body()
        let language = Language.from(fileExtension: url.pathExtension)
        emit(.fileFinished(url, language: language, findingCount: findings, duration: ContinuousClock.now - start))
        return value
    }
}
