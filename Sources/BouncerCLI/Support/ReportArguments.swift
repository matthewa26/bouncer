import ArgumentParser
import BouncerCore
import BouncerReporting

/// The options `check` and `review` share for choosing which findings a report shows and how: filters,
/// paging, grouping, and summary-only output.
struct ReportArguments: ParsableArguments {
    @Option(name: .customLong("rule"), help: "Report only this rule's findings. Repeatable.")
    var rules: [String] = []

    @Option(
        name: .customLong("path"), help: "Report only files matching this glob, relative to the repo root. Repeatable."
    )
    var paths: [String] = []

    @Option(help: "Report only findings at least this severe: info, warning, or error.")
    var minSeverity: Severity?

    @Option(help: "Report at most this many findings, in file, line, and rule order.")
    var limit: Int?

    @Option(help: "Skip this many findings, in file, line, and rule order, before reporting.")
    var offset = 0

    @Option(help: "file or rule: how agent and console output group findings. agent defaults to file.")
    var groupBy: ReportGrouping?

    @Flag(help: "Print only the summary: totals, top rules and files, and time. JSON omits findings.")
    var summary = false

    /// Rejects a negative page size or offset.
    ///
    /// - Throws: A `ValidationError` naming the bad option.
    func validate() throws {
        if let limit, limit < 0 { throw ValidationError("--limit can't be negative.") }
        if offset < 0 { throw ValidationError("--offset can't be negative.") }
    }

    /// The filters and page these options ask for.
    var selection: FindingSelection {
        var selection = FindingSelection()
        selection.rules = rules
        selection.paths = paths
        selection.minimumSeverity = minSeverity
        selection.limit = limit
        selection.offset = offset
        return selection
    }
}
