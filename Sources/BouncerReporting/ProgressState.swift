import Foundation
import BouncerCore

/// Where a run is: the current step, how far through its files it is, and the file being worked on.
struct ProgressState: Equatable {
    /// The step under way, or `nil` before the first one starts.
    var phase: AnalysisPhase?
    /// How many files the step will go through, if known.
    var total: Int?
    /// How many of those files are done.
    var done = 0
    /// The file being worked on, as shown to the user.
    var currentFile: String?
    /// The last tenth of the step a heartbeat was printed for.
    var lastDecile = 0

    /// Resets the state for a new step.
    ///
    /// - Parameters:
    ///   - phase: The step.
    ///   - total: How many files it will go through, if known.
    mutating func start(_ phase: AnalysisPhase, total: Int?) {
        self = ProgressState(phase: phase, total: total)
    }

    /// How far through its files the step is, from 0 to 1, or `nil` when the total isn't known.
    var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return Double(min(done, total)) / Double(total)
    }
}

/// How one step is described in progress output: while it runs, once it's done, and what it counts.
struct PhaseLabel {
    /// The step under way, such as `analyzing`.
    let doing: String
    /// The finished step, such as `analyzed`.
    let done: String
    /// What a known total counts, such as `files`, or `nil` for a step that doesn't count files.
    var unit: String? = nil
}

/// One finished file, as the verbose log describes it.
struct FileReport {
    /// The file's path, as shown to the user.
    let path: String
    /// Its language.
    let language: Language
    /// How many findings it produced.
    let findings: Int
    /// How long it took.
    let duration: Duration
}

/// How often `ProgressRenderer` redraws and prints heartbeats, and the escape sequence it redraws with.
enum ProgressPacing {
    /// The shortest gap between two redraws of the live line.
    static let redrawInterval = Duration.milliseconds(100)
    /// How long plain output may go quiet during a step before a heartbeat says it's still going.
    static let quietLimit = Duration.seconds(30)
    /// The shortest gap between two of plain output's every-tenth-of-the-way heartbeats.
    static let heartbeatSpacing = Duration.seconds(5)
    /// How many parts a step's files are split into for plain output's heartbeats: one per tenth.
    static let heartbeatSteps = 10
    /// Clears the current terminal line and returns to its start.
    static let clearLine = "\r\u{1B}[2K"
}

extension Duration {
    /// How many attoseconds make a second.
    private static let attosecondsPerSecond = 1e18

    /// The duration in seconds, as a floating-point number.
    var secondsValue: Double {
        Double(components.seconds) + Double(components.attoseconds) / Self.attosecondsPerSecond
    }
}
