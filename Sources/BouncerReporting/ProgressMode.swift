/// What `--progress` asked for: a redrawn status line, one line per step, nothing, or a choice made from
/// how Bouncer was invoked.
public enum ProgressMode: String, Sendable, CaseIterable {
    /// Off for agent invocations, a live line when standard error is a terminal, and plain lines otherwise.
    case auto
    /// One status line, redrawn in place.
    case live
    /// One line as each step starts and finishes, with an occasional heartbeat.
    case plain
    /// No progress output.
    case off

    /// The style each mode other than `auto` always gets.
    private static let fixedStyles: [ProgressMode: ProgressStyle] = [.live: .live, .plain: .plain, .off: .off]

    /// Decides how this run shows its progress.
    ///
    /// `--verbose` always gets plain lines, so its log lines never interleave with a redrawn status line.
    ///
    /// - Parameter invocation: How Bouncer was invoked.
    /// - Returns: The style to render with.
    public func style(for invocation: ProgressInvocation) -> ProgressStyle {
        if invocation.verbose { return .plain }
        guard self == .auto else { return Self.fixedStyles[self] ?? .off }
        if invocation.isAgentInvocation { return .off }
        return invocation.standardErrorIsTerminal ? .live : .plain
    }
}

/// What `ProgressMode.style(for:)` needs to know about how Bouncer was invoked.
public struct ProgressInvocation: Sendable, Equatable {
    /// Whether `--verbose` was given.
    public var verbose = false
    /// Whether a coding agent is likely reading the output, as with `--files`, `--stdin`, or
    /// `review --format json`.
    public var isAgentInvocation = false
    /// Whether standard error is attached to a terminal that can redraw a line.
    public var standardErrorIsTerminal = false

    /// Creates a description of a plain, non-verbose, non-terminal invocation; set the fields that differ.
    public init() {}
}

/// How a run's progress is actually shown, once `ProgressMode.auto` has been decided.
public enum ProgressStyle: Sendable, Equatable {
    /// One status line, redrawn in place.
    case live
    /// One line per step, with an occasional heartbeat.
    case plain
    /// Nothing.
    case off
}
