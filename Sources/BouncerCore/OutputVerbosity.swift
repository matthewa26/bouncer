/// How much detail a `Reporter` includes in its console output.
///
/// Only affects human-facing console output - `JSONReporter` always emits the
/// complete structured findings regardless of this setting, since machine
/// consumers want completeness rather than a trimmed-down summary.
public enum OutputVerbosity: String, Codable, Sendable {
    /// Every finding, with full context.
    case verbose
    /// One line per finding. The default.
    case normal
    /// Only the final pass/fail line and a count, no per-finding detail.
    case quiet
    /// A single summary line: total count and a breakdown by severity.
    case condensed
}
