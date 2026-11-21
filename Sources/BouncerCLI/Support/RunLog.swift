import Foundation
import BouncerCore
import BouncerReporting

/// One run's progress display and verbose log on standard error, with the ticker that keeps it moving.
struct RunLog {
    /// Renders the run's events.
    let renderer: ProgressRenderer
    private let ticker: DispatchSourceTimer?
    /// How often a live line is ticked, so its clock moves even while one file takes a long time.
    private static let liveTick = DispatchTimeInterval.milliseconds(100)
    /// How often plain output is ticked, to check whether a heartbeat is due.
    private static let plainTick = DispatchTimeInterval.seconds(1)

    /// Starts the progress display an invocation asked for.
    ///
    /// - Parameters:
    ///   - arguments: The `--progress` and `--verbose` options.
    ///   - invocation: What's known about the caller, such as whether a coding agent is likely reading the
    ///     output, which turns `auto` off. Its verbose and terminal fields are filled in here.
    ///   - root: The repository root, which file paths are shown relative to.
    ///   - context: What the command already knows about the run, logged first when verbose.
    /// - Returns: The running log.
    static func start(
        _ arguments: ProgressArguments, invocation: ProgressInvocation, root: URL?, context: [String]
    ) -> RunLog {
        var settings = ProgressRenderer.Settings(style: style(arguments, invocation: invocation))
        settings.verbose = arguments.verbose
        settings.root = root
        settings.width = Terminal.standardErrorColumns
        settings.analyzerNames = AnalyzerFactory.makeKnownAnalyzers().mapValues { String(describing: type(of: $0)) }
        settings.fallbackAnalyzerName = String(describing: type(of: AnalyzerFactory.makeFallbackAnalyzer()))
        let renderer = ProgressRenderer(settings: settings, write: writeToStandardError, now: monotonicNow)
        context.forEach(renderer.log)
        return RunLog(renderer: renderer, ticker: renderer.isActive ? startTicker(renderer, settings.style) : nil)
    }

    /// Passes the run's events to the renderer.
    var onEvent: AnalysisEventHandler {
        let renderer = renderer
        return { renderer.handle($0) }
    }

    /// Stops the ticker and clears the live line, before anything else is printed.
    func finish() {
        ticker?.cancel()
        renderer.finish()
    }

    /// Describes where this run's config came from, for the verbose log.
    ///
    /// - Parameters:
    ///   - repoRoot: The repository root.
    ///   - profile: The `--profile` given, if any.
    ///   - explicitPath: The `--config` given, if any.
    /// - Returns: One line per source.
    static func configLines(repoRoot: URL, profile: String?, explicitPath: String?) -> [String] {
        let tail = ["profile: \(profile ?? "none")", "repo root: \(repoRoot.path)"]
        if let explicitPath { return ["config: \(explicitPath) (from --config; other layers skipped)"] + tail }
        let layers = [("global", BouncerPaths.globalConfig), ("repo", BouncerPaths.repoConfig(repoRoot: repoRoot))]
        return layers.map { name, url in
            let found = FileManager.default.fileExists(atPath: url.path) ? "found" : "not found"
            return "config: \(name) \(url.path) (\(found))"
        } + tail
    }

    /// Decides the style, falling back to plain lines where a live line can't be drawn.
    ///
    /// - Parameters:
    ///   - arguments: The `--progress` and `--verbose` options.
    ///   - invocation: What's known about the caller.
    /// - Returns: The style to render with.
    private static func style(_ arguments: ProgressArguments, invocation: ProgressInvocation) -> ProgressStyle {
        var invocation = invocation
        invocation.verbose = arguments.verbose
        let dumb = ProcessInfo.processInfo.environment["TERM"] == "dumb"
        invocation.standardErrorIsTerminal = Terminal.standardErrorIsInteractive && !dumb
        let style = arguments.progress.style(for: invocation)
        guard style == .live, !Terminal.enableVirtualTerminalOnStandardError() else { return style }
        return .plain
    }

    /// Starts a background timer that ticks the renderer: often for a live line, once a second for plain lines.
    ///
    /// - Parameters:
    ///   - renderer: The renderer to tick.
    ///   - style: Its style.
    /// - Returns: The running timer.
    private static func startTicker(_ renderer: ProgressRenderer, _ style: ProgressStyle) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        let interval = style == .live ? liveTick : plainTick
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { renderer.tick() }
        timer.resume()
        return timer
    }
}

/// Writes progress output to standard error, unbuffered.
///
/// - Parameter text: The output.
@Sendable private func writeToStandardError(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
}

/// Reads the monotonic clock, as a duration since an arbitrary fixed point.
///
/// - Returns: The current reading.
@Sendable private func monotonicNow() -> Duration {
    ContinuousClock.now - RunLogClock.origin
}

/// The fixed point `monotonicNow` measures from.
private enum RunLogClock {
    /// The first time the clock was read.
    static let origin = ContinuousClock.now
}
