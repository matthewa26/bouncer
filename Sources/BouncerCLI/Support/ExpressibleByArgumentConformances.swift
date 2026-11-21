import ArgumentParser
import BouncerCore
import BouncerReporting

extension Severity: ExpressibleByArgument {}
extension OutputVerbosity: ExpressibleByArgument {}
extension ProgressMode: ExpressibleByArgument {}

/// The output structure a `Reporter` renders as: console text, a Markdown table, JSON, an HTML page, or Xcode
/// build diagnostics.
public enum OutputFormat: String, ExpressibleByArgument {
    case console
    case table
    case json
    case html
    case xcode

    /// The help text the `--format` options show.
    static let help = "console, table, json, html, or xcode. html is written to .bouncer-cache/report.html unless "
        + "--output names another file; xcode prints diagnostics an Xcode Run Script phase shows inline."
}
