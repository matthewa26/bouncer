import Foundation
import BouncerCore

/// Formats progress lines, durations, and counts for `ProgressRenderer` and the end-of-run summary.
enum ProgressText {
    /// Each step's wording.
    static let labels: [AnalysisPhase: PhaseLabel] = [
        .preCheckHooks: PhaseLabel(doing: "running preCheck hooks", done: "ran preCheck hooks"),
        .discoverFiles: PhaseLabel(doing: "listing files", done: "listed files"),
        .analyzeFiles: PhaseLabel(doing: "analyzing", done: "analyzed", unit: "files"),
        .baseline: PhaseLabel(doing: "applying the baseline", done: "applied the baseline"),
        .coverage: PhaseLabel(doing: "reading the coverage report", done: "read the coverage report"),
        .listProjectFiles: PhaseLabel(doing: "listing project files", done: "listed project files"),
        .projectIndex: PhaseLabel(doing: "indexing", done: "indexed", unit: "project files"),
        .projectRules: PhaseLabel(doing: "running project rules", done: "ran project rules"),
        .changeRules: PhaseLabel(doing: "running change rules", done: "ran change rules"),
        .suppressions: PhaseLabel(doing: "applying suppression comments", done: "applied suppression comments"),
        .report: PhaseLabel(doing: "rendering the report", done: "rendered the report"),
        .postCheckHooks: PhaseLabel(doing: "running postCheck hooks", done: "ran postCheck hooks")
    ]

    /// The number of cells in the live line's bar.
    static let barCells = 20
    /// The narrowest room worth showing a truncated path in.
    static let minimumPathRoom = 8
    /// The columns the live line's separators take: two spaces on each side of the path.
    static let separatorColumns = 4
    /// How many digits sit between thousands separators.
    private static let digitsPerGroup = 3
    /// Turns a fraction into a percentage.
    private static let percentScale = 100.0
    /// Turns seconds into milliseconds.
    private static let millisecondsPerSecond = 1000.0
    /// Seconds in a minute, and minutes in an hour.
    private static let sixty = 60

    /// Describes a step, with its file count when it has one.
    ///
    /// - Parameters:
    ///   - phase: The step.
    ///   - count: The file count to show, if any.
    ///   - tense: Which wording to use: `\.doing` while it runs, `\.done` once it's finished.
    /// - Returns: Text such as `analyzing 12,345 files`.
    static func describe(_ phase: AnalysisPhase, count: Int?, tense: KeyPath<PhaseLabel, String>) -> String {
        let label = labels[phase] ?? PhaseLabel(doing: phase.rawValue, done: phase.rawValue)
        let verb = label[keyPath: tense]
        guard let unit = label.unit, let count else { return verb }
        return "\(verb) \(grouped(count)) \(count == 1 ? String(unit.dropLast()) : unit)"
    }

    /// Describes one finished file for the verbose log.
    ///
    /// - Parameters:
    ///   - file: The file and how it went.
    ///   - analyzer: The name of the analyzer that handled it.
    ///   - phase: The step it was part of, which decides whether it was analyzed or indexed.
    /// - Returns: Text such as `analyzed Sources/A.swift (swift, SwiftSyntaxAnalyzer): 3 findings in 12ms`.
    static func fileLine(_ file: FileReport, analyzer: String, phase: AnalysisPhase?) -> String {
        let what = "\(file.path) (\(name(of: file.language)), \(analyzer))"
        let time = seconds(file.duration)
        guard phase == .analyzeFiles else { return "indexed \(what) in \(time)" }
        return "analyzed \(what): \(file.findings) finding\(file.findings == 1 ? "" : "s") in \(time)"
    }

    /// Whether a step runs commands whose own output goes to the terminal, so a live line must stay clear.
    ///
    /// - Parameter phase: The step.
    /// - Returns: `true` for the hook steps.
    static func printsOutput(_ phase: AnalysisPhase) -> Bool {
        phase == .preCheckHooks || phase == .postCheckHooks
    }

    /// The plain-mode heartbeat: how far through its files the current step is, and what it's working on.
    ///
    /// - Parameters:
    ///   - state: Where the run is.
    ///   - elapsed: Time since the run started.
    /// - Returns: Text such as `still analyzing: 4,000 of 12,345 files (32%), 12.0s elapsed; at Sources/A.swift`.
    static func heartbeat(_ state: ProgressState, elapsed: Duration) -> String {
        let phase = state.phase.map { describe($0, count: nil, tense: \.doing) } ?? "working"
        let unit = state.phase.flatMap { labels[$0]?.unit } ?? "files"
        let counts = state.total.map { ": \(grouped(state.done)) of \(grouped($0)) \(unit) (\(percent(state)))" }
        let file = state.currentFile.map { "; at \($0)" } ?? ""
        return "still \(phase)\(counts ?? ""), \(seconds(elapsed)) elapsed\(file)"
    }

    /// The live status line: a bar, the file count and percentage, the step, the current file, and the time.
    ///
    /// - Parameters:
    ///   - state: Where the run is.
    ///   - elapsed: Time since the run started.
    ///   - width: The terminal's width in columns; the line is kept one column shorter.
    /// - Returns: The line, without any cursor control.
    static func liveLine(_ state: ProgressState, elapsed: Duration, width: Int) -> String {
        let head = liveHead(state)
        let tail = clock(elapsed)
        let room = width - 1 - head.count - tail.count - separatorColumns
        let file = state.currentFile.map { truncated($0, to: room) } ?? ""
        let line = [head, file, tail].filter { !$0.isEmpty }.joined(separator: "  ")
        return String(line.prefix(max(width - 1, 0)))
    }

    /// The start of the live line: the bar and counts when the step's total is known, then the step.
    ///
    /// - Parameter state: Where the run is.
    /// - Returns: Text such as `[######--------------] 4,000/12,345 32% analyzing`.
    private static func liveHead(_ state: ProgressState) -> String {
        let phase = state.phase.map { describe($0, count: nil, tense: \.doing) } ?? "starting"
        guard let fraction = state.fraction, let total = state.total else { return phase }
        return "\(bar(fraction)) \(grouped(state.done))/\(grouped(total)) \(percent(state)) \(phase)"
    }

    /// Draws a `barCells`-wide text progress bar.
    ///
    /// - Parameter fraction: How full it is, from 0 to 1.
    /// - Returns: Text such as `[#####---------------]`.
    static func bar(_ fraction: Double) -> String {
        let filled = min(max(Int(fraction * Double(barCells)), 0), barCells)
        return "[" + String(repeating: "#", count: filled) + String(repeating: "-", count: barCells - filled) + "]"
    }

    /// Shows how far through its files a step is as a whole percentage.
    ///
    /// - Parameter state: Where the run is.
    /// - Returns: Text such as `32%`, or `?%` when the total isn't known.
    private static func percent(_ state: ProgressState) -> String {
        state.fraction.map { "\(Int($0 * percentScale))%" } ?? "?%"
    }

    /// Shortens text from the left to fit, so a path keeps its file name.
    ///
    /// - Parameters:
    ///   - text: The text, usually a path.
    ///   - limit: The most characters to keep.
    /// - Returns: The text, `...` followed by its end, or nothing if there's too little room to be useful.
    static func truncated(_ text: String, to limit: Int) -> String {
        let ellipsis = "..."
        guard text.count > limit else { return text }
        guard limit >= minimumPathRoom else { return "" }
        return ellipsis + String(text.suffix(limit - ellipsis.count))
    }

    /// Writes a count with thousands separators, the same in every locale.
    ///
    /// - Parameter count: The count.
    /// - Returns: Text such as `12,345`.
    static func grouped(_ count: Int) -> String {
        let digits = Array(String(count.magnitude))
        let body = digits.enumerated().map { index, digit in
            (index > 0 && (digits.count - index) % digitsPerGroup == 0 ? "," : "") + String(digit)
        }
        return (count < 0 ? "-" : "") + body.joined()
    }

    /// Writes a duration for a log line.
    ///
    /// - Parameter duration: The duration.
    /// - Returns: Text such as `12ms`, `41.2s`, `3m 05s`, or `1h 02m`.
    static func seconds(_ duration: Duration) -> String {
        let total = duration.secondsValue
        if total < 1 { return "\(Int(total * millisecondsPerSecond))ms" }
        if total < Double(sixty) { return String(format: "%.1fs", total) }
        let (hours, minutes, secs) = parts(duration)
        if hours == 0 { return String(format: "%dm %02ds", minutes, secs) }
        return String(format: "%dh %02dm", hours, minutes)
    }

    /// Writes a duration as a running clock, for the live line.
    ///
    /// - Parameter duration: The duration.
    /// - Returns: Text such as `0:12` or `1:02:03`.
    static func clock(_ duration: Duration) -> String {
        let (hours, minutes, secs) = parts(duration)
        guard hours > 0 else { return String(format: "%d:%02d", minutes, secs) }
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }

    /// Splits a duration into whole hours, minutes, and seconds.
    ///
    /// - Parameter duration: The duration.
    /// - Returns: The parts, with minutes and seconds below 60.
    private static func parts(_ duration: Duration) -> (hours: Int, minutes: Int, seconds: Int) {
        let whole = Int(duration.secondsValue)
        return (whole / (sixty * sixty), whole / sixty % sixty, whole % sixty)
    }

    /// Names a language the way a log line shows it.
    ///
    /// - Parameter language: The language.
    /// - Returns: Its name, such as `swift`, or an unrecognized file's extension.
    static func name(of language: Language) -> String {
        guard case .other(let fileExtension) = language else { return String(describing: language) }
        return fileExtension.isEmpty ? "other" : fileExtension
    }
}
