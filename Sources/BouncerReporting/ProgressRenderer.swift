import Foundation
import BouncerCore

/// Turns a run's `AnalysisEvent`s into progress output: a redrawn status line, plain lines, or a verbose log.
///
/// Everything it writes goes to the injected sink (standard error, in the command line), and every time it
/// reads comes from the injected monotonic clock, so tests can drive it deterministically. It's safe to call
/// from the analysis thread and a ticker thread at once.
public final class ProgressRenderer: @unchecked Sendable { // bouncer:disable-line swift-unchecked-sendable -- NSLock
    /// How a renderer presents a run.
    public struct Settings: Sendable {
        /// Live, plain, or off.
        public var style: ProgressStyle
        /// Whether to log every file, note, and `log(_:)` message, with a timestamp on each line.
        public var verbose = false
        /// The repository root, which file paths are shown relative to.
        public var root: URL?
        /// The terminal's width in columns, which the live line is kept within.
        public var width = 80
        /// Each language's analyzer name, for verbose file lines.
        public var analyzerNames: [Language: String] = [:]
        /// The analyzer name for a language without an entry in `analyzerNames`.
        public var fallbackAnalyzerName = "heuristic"

        /// Creates settings with the defaults for everything but the style.
        ///
        /// - Parameter style: Live, plain, or off.
        public init(style: ProgressStyle) {
            self.style = style
        }
    }

    private let settings: Settings
    private let write: @Sendable (String) -> Void
    private let now: @Sendable () -> Duration
    private let lock = NSLock()
    private let started: Duration
    private var state = ProgressState()
    private var lastDraw: Duration?
    private var lastLine: Duration
    private var lineVisible = false
    private var suspended = false
    private var finished = false

    /// Creates a renderer.
    ///
    /// - Parameters:
    ///   - settings: How to present the run.
    ///   - write: Receives every piece of output, unbuffered.
    ///   - now: A monotonic clock; only differences between its readings matter.
    public init(
        settings: Settings, write: @escaping @Sendable (String) -> Void, now: @escaping @Sendable () -> Duration
    ) {
        self.settings = settings
        self.write = write
        self.now = now
        started = now()
        lastLine = started
    }

    /// Whether this renderer writes anything at all.
    public var isActive: Bool { settings.style != .off }

    /// Updates the output for one event.
    ///
    /// - Parameter event: The event.
    public func handle(_ event: AnalysisEvent) {
        locked {
            guard isActive, !finished else { return }
            process(event)
        }
    }

    /// Redraws the live line so its clock keeps moving, or prints a plain heartbeat after a long quiet spell.
    public func tick() {
        locked {
            guard isActive, !finished, !suspended else { return }
            if settings.style == .live { return drawThrottled() }
            guard state.phase != nil, now() - lastLine >= ProgressPacing.quietLimit else { return }
            line(ProgressText.heartbeat(state, elapsed: now() - started))
        }
    }

    /// Logs a message from outside the engine, such as where config came from, when verbose.
    ///
    /// - Parameter message: The message.
    public func log(_ message: String) {
        locked {
            guard settings.verbose, isActive, !finished else { return }
            line(message)
        }
    }

    /// Clears the live line and stops all further output, before the report or an error is printed.
    public func finish() {
        locked {
            clearLive()
            finished = true
        }
    }

    /// Dispatches one event.
    ///
    /// - Parameter event: The event.
    private func process(_ event: AnalysisEvent) {
        switch event {
        case let .phaseStarted(phase, total): startPhase(phase, total: total)
        case let .fileStarted(url):
            state.currentFile = display(url)
            drawThrottled()
        case let .fileFinished(url, language, count, duration): finishFile(url, language, count, duration)
        case let .phaseFinished(phase, duration): finishPhase(phase, duration: duration)
        case let .note(text): if settings.style == .plain { line(text) }
        }
    }

    /// Starts a step: a plain line, and a live redraw unless the step prints output of its own.
    ///
    /// - Parameters:
    ///   - phase: The step.
    ///   - total: How many files it will go through, if known.
    private func startPhase(_ phase: AnalysisPhase, total: Int?) {
        state.start(phase, total: total)
        if settings.style == .plain { line(ProgressText.describe(phase, count: total, tense: \.doing) + "...") }
        suspended = ProgressText.printsOutput(phase)
        if suspended { clearLive() } else { drawNow() }
    }

    /// Counts a finished file, logging it when verbose and printing a heartbeat at each tenth of the way.
    ///
    /// - Parameters:
    ///   - url: The file.
    ///   - language: Its language.
    ///   - count: How many findings it produced.
    ///   - duration: How long it took.
    private func finishFile(_ url: URL, _ language: Language, _ count: Int, _ duration: Duration) {
        state.done += 1
        let file = FileReport(path: display(url), language: language, findings: count, duration: duration)
        if let text = settings.verbose ? verboseLine(file) : decileHeartbeat() { line(text) }
        drawThrottled()
    }

    /// Describes a finished file for the verbose log, naming the analyzer its language uses.
    ///
    /// - Parameter file: The file and how it went.
    /// - Returns: The log line.
    private func verboseLine(_ file: FileReport) -> String {
        let analyzer = settings.analyzerNames[file.language] ?? settings.fallbackAnalyzerName
        return ProgressText.fileLine(file, analyzer: analyzer, phase: state.phase)
    }

    /// Ends a step with a plain line giving its file count and time.
    ///
    /// - Parameters:
    ///   - phase: The step.
    ///   - duration: How long it took.
    private func finishPhase(_ phase: AnalysisPhase, duration: Duration) {
        let count = state.total == nil ? nil : state.done
        let text = ProgressText.describe(phase, count: count, tense: \.done)
        if settings.style == .plain { line("\(text) in \(ProgressText.seconds(duration))") }
        state = ProgressState()
        suspended = false
    }

    /// Builds a plain heartbeat when the step has passed another tenth of its files, if it's been a while.
    ///
    /// - Returns: The heartbeat, or `nil` when none is due.
    private func decileHeartbeat() -> String? {
        guard settings.style == .plain, let total = state.total, total > 0 else { return nil }
        let decile = state.done * ProgressPacing.heartbeatSteps / total
        guard decile > state.lastDecile, decile < ProgressPacing.heartbeatSteps else { return nil }
        guard now() - lastLine >= ProgressPacing.heartbeatSpacing else { return nil }
        state.lastDecile = decile
        return ProgressText.heartbeat(state, elapsed: now() - started)
    }

    /// Redraws the live line unless it was redrawn less than `ProgressPacing.redrawInterval` ago.
    private func drawThrottled() {
        if let lastDraw, now() - lastDraw < ProgressPacing.redrawInterval { return }
        drawNow()
    }

    /// Redraws the live line, when there is one, a step is under way, and no hook output needs the terminal.
    private func drawNow() {
        guard settings.style == .live, !suspended, state.phase != nil else { return }
        let time = now()
        lastDraw = time
        let text = ProgressText.liveLine(state, elapsed: time - started, width: settings.width)
        write(ProgressPacing.clearLine + text)
        lineVisible = true
    }

    /// Clears the live line, if one is showing.
    private func clearLive() {
        guard lineVisible else { return }
        write(ProgressPacing.clearLine)
        lineVisible = false
    }

    /// Writes one whole line, prefixed with `[bouncer]` and, when verbose, the time since the run started.
    ///
    /// - Parameter text: The line's text.
    private func line(_ text: String) {
        clearLive()
        let time = now()
        let stamp = settings.verbose ? " +" + String(format: "%.3fs", (time - started).secondsValue) : ""
        write("[bouncer\(stamp)] \(text)\n")
        lastLine = time
    }

    /// Shows a file's path relative to the repository root.
    ///
    /// - Parameter url: The file.
    /// - Returns: Its repo-relative path, or its full path without a root.
    private func display(_ url: URL) -> String {
        settings.root.map { RepoPath.relative(url, to: $0) } ?? url.path
    }

    /// Runs a body while holding the renderer's lock.
    ///
    /// - Parameter body: The body.
    private func locked(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body()
    }
}
