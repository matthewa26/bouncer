/// The wording a long-lived agent session, such as `bouncer mcp`, uses for a result's age and a scan's progress.
public enum AgentSessionText {
    /// Seconds in a minute.
    private static let minute = 60
    /// Seconds in an hour.
    private static let hour = 3_600
    /// Seconds in a day.
    private static let day = 86_400
    /// What a fraction is multiplied by to give a percentage.
    private static let percentScale = 100

    /// Says how long ago something happened, coarsely.
    ///
    /// - Parameter seconds: How many seconds ago.
    /// - Returns: `just now`, `42 s ago`, `4 min ago`, `2 h ago`, or `3 days ago`.
    public static func age(seconds: Int) -> String {
        guard seconds >= 1 else { return "just now" }
        let units = [(minute, 1, " s"), (hour, minute, " min"), (day, hour, " h")]
        if let (_, size, name) = units.first(where: { seconds < $0.0 }) { return "\(seconds / size)\(name) ago" }
        let days = seconds / day
        return "\(days) day\(days == 1 ? "" : "s") ago"
    }

    /// The line that opens a response read from a result that isn't refreshed before each call.
    ///
    /// - Parameter seconds: How old the result is.
    /// - Returns: A line such as `Results from 4 min ago; verify re-checks files you edited.`
    public static func ageHeader(seconds: Int) -> String {
        "Results from \(age(seconds: seconds)); verify re-checks files you edited."
    }

    /// Describes a running scan's progress.
    ///
    /// - Parameters:
    ///   - done: How many files the scan has analyzed.
    ///   - total: How many it will analyze, or `nil` while it's still listing them.
    ///   - elapsedSeconds: How long it has run.
    ///   - step: What it's doing once every file is analyzed, such as `running project rules`.
    /// - Returns: A line such as `Scanning: 42% (120 of 284 files), 3s elapsed. Call status.`
    public static func progress(done: Int, total: Int?, elapsedSeconds: Int, step: String? = nil) -> String {
        "Scanning: \(stage(done: done, total: total, step: step)), \(elapsedSeconds)s elapsed. Call status."
    }

    /// Describes what a running scan is doing.
    ///
    /// - Parameters:
    ///   - done: How many files the scan has analyzed.
    ///   - total: How many it will analyze, if known.
    ///   - step: What it's doing once every file is analyzed.
    /// - Returns: `listing files`, `42% (120 of 284 files)`, or the step.
    private static func stage(done: Int, total: Int?, step: String?) -> String {
        guard let total else { return "listing files" }
        if done >= total, let step { return "all \(total) files analyzed, \(step)" }
        let percent = total == 0 ? percentScale : min(percentScale, done * percentScale / total)
        return "\(percent)% (\(done) of \(total) files)"
    }
}
