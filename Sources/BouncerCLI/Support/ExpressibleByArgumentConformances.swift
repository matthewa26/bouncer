import ArgumentParser
import BouncerCore
import BouncerReporting

extension Severity: ExpressibleByArgument {}
extension OutputVerbosity: ExpressibleByArgument {}
extension ProgressMode: ExpressibleByArgument {}

/// The output structure a `Reporter` renders as: console text, a Markdown table, JSON, or an HTML page.
public enum OutputFormat: String, ExpressibleByArgument {
    case console
    case table
    case json
    case html

    /// The help text the `--format` options show.
    static let help = "console, table, json, or html. html is written to .bouncer-cache/report.html unless --output "
        + "names another file."
}
