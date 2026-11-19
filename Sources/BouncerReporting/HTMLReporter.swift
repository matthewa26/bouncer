import Foundation
import BouncerCore

/// Renders an `AnalysisResult` as one self-contained HTML page, with no external assets, so it opens straight
/// from disk: a table view to search, filter, and sort the findings, and a JSON view of the same data as
/// `--format json` prints, ready to copy into another tool.
public struct HTMLReporter: Reporter {
    private let repoRoot: URL

    /// Creates an HTML reporter.
    ///
    /// - Parameter repoRoot: The repository root, which locations are shown relative to and the title names.
    public init(repoRoot: URL) {
        self.repoRoot = repoRoot
    }

    /// Renders a result as an HTML page. Every verbosity renders the full page; the table filters replace it.
    ///
    /// - Parameters:
    ///   - result: The analysis result to render.
    ///   - verbosity: Ignored; the page always holds every finding.
    /// - Returns: The page.
    public func report(_ result: AnalysisResult, verbosity: OutputVerbosity) -> String {
        let json = JSONReporter().report(result, verbosity: .normal)
        let rows = Self.scriptSafe(Self.encode(ReportRow.rows(result.findings, repoRoot: repoRoot)))
        return HTMLTemplate.page(
            title: Self.escape("Bouncer report: \(repoRoot.lastPathComponent)"),
            summary: Self.escape(ReportSummary.line(result)), rows: rows, json: Self.escape(json)
        )
    }

    /// Encodes the rows as compact JSON for the page's script.
    ///
    /// - Parameter rows: The rows.
    /// - Returns: The JSON array, or `[]` if encoding fails.
    private static func encode(_ rows: [ReportRow]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(rows)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    /// Makes JSON safe inside a `<script>` element: `<`, `>`, and `&` only occur inside JSON strings, so writing
    /// them as `\u003c`-style escapes leaves the data unchanged but gives the HTML parser nothing to read as a tag
    /// or comment, such as a `</script>` that would end the element early.
    ///
    /// - Parameter json: The JSON.
    /// - Returns: The same JSON, with those characters escaped.
    private static func scriptSafe(_ json: String) -> String {
        json.replacingOccurrences(of: "&", with: "\\u0026").replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
    }

    /// Escapes text for HTML element content.
    ///
    /// - Parameter text: The text.
    /// - Returns: The escaped text.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
