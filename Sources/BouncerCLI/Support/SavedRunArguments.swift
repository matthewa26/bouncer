import ArgumentParser

/// `review`'s options for the saved last run in `.bouncer-cache/last-run.json`.
struct SavedRunArguments: ParsableArguments {
    @Flag(help: "Start from the saved last run, analyzing only files changed since. The default once a run is saved.")
    var fromLastRun = false

    @Flag(help: "Analyze every file, ignoring the saved last run; the result is still saved.")
    var full = false

    @Flag(help: "Don't save this run's result to .bouncer-cache/last-run.json, or start from it.")
    var noSaveRun = false

    /// Rejects asking for both a fresh and an incremental run.
    ///
    /// - Throws: `ValidationError` if `--full` and `--from-last-run` are both given.
    func validate() throws {
        if full && fromLastRun { throw ValidationError("--full and --from-last-run can't be combined.") }
    }
}
