import ArgumentParser
import BouncerCore

extension Severity: ExpressibleByArgument {}
extension OutputVerbosity: ExpressibleByArgument {}

/// The output structure a `Reporter` renders as: plain console text or JSON.
public enum OutputFormat: String, ExpressibleByArgument {
    case console
    case json
}
