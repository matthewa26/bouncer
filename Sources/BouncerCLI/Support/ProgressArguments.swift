import ArgumentParser
import BouncerReporting

/// The `--progress`, `--verbose`, and `--jobs` options `check`, `review`, and `baseline update` share: how a run
/// shows its progress and how many threads it runs on, neither of which changes what it finds.
struct ProgressArguments: ParsableArguments {
    @Option(help: "auto, live, plain, or off. Progress goes to stderr; auto is off for agent invocations.")
    var progress: ProgressMode = .auto

    @Flag(name: [.customLong("verbose"), .customShort("v")], help: "Log every step and file to stderr.")
    var verbose = false

    @Option(
        name: [.customLong("jobs"), .customShort("j")],
        help: "How many files to analyze at once. Defaults to .bouncer's jobs, else one per processor core."
    )
    var jobs: Int?

    /// Rejects a thread count below one.
    ///
    /// - Throws: A `ValidationError` naming `--jobs`.
    func validate() throws {
        if let jobs, jobs < 1 { throw ValidationError("--jobs must be at least 1.") }
    }
}
