import ArgumentParser
import BouncerCore
import BouncerReporting

extension Severity: ExpressibleByArgument {}
extension OutputVerbosity: ExpressibleByArgument {}
extension ProgressMode: ExpressibleByArgument {}
extension ReportGrouping: ExpressibleByArgument {}

/// The output structure a `Reporter` renders as: console text, a Markdown table, JSON, an HTML page, Xcode
/// build diagnostics, or compact text for a coding agent.
public enum OutputFormat: String, ExpressibleByArgument {
    case console
    case table
    case json
    case html
    case xcode
    case agent

    /// The help text the `--format` options show.
    static let help = "console, table, json, html, xcode, or agent. html is written to .bouncer-cache/report.html "
        + "unless --output names another file; xcode prints diagnostics an Xcode Run Script phase shows inline; "
        + "agent prints findings grouped by file in as few tokens as possible."
}
