import Foundation
import BouncerCore

/// Renders an `AnalysisResult` as one self-contained HTML page, with no external assets, so it opens straight
/// from disk: a table view to search, filter, and sort the findings, and a JSON view that previews, copies, and
/// downloads the same data as `--format json` prints. The findings are embedded once, in a compact form, and the
/// page renders them a screenful at a time, so it stays usable with millions of findings.
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
        let data = Self.scriptSafe(Self.encode(HTMLReportData(result: result, repoRoot: repoRoot)))
        return HTMLTemplate.page(
            title: Self.escape("Bouncer report: \(repoRoot.lastPathComponent)"),
            summary: Self.escape(ReportSummary.line(result)), data: data
        )
    }

    /// Encodes the report data as compact JSON for the page's script.
    ///
    /// - Parameter data: The report data.
    /// - Returns: The JSON object's UTF-8 bytes, or `{}` if encoding fails.
    private static func encode(_ data: HTMLReportData) -> Data {
        (try? JSONEncoder().encode(data)) ?? Data("{}".utf8)
    }

    /// Makes JSON safe inside a `<script>` element: `<`, `>`, and `&` only occur inside JSON strings, so writing
    /// them as `\u003c`-style escapes leaves the data unchanged but gives the HTML parser nothing to read as a tag
    /// or comment, such as a `</script>` that would end the element early. It works in one pass over the bytes,
    /// since the data can run to hundreds of megabytes.
    ///
    /// - Parameter json: The JSON's UTF-8 bytes.
    /// - Returns: The same JSON, with those characters escaped.
    private static func scriptSafe(_ json: Data) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(json.count)
        json.withUnsafeBytes { buffer in
            for byte in buffer { appendScriptSafe(byte, to: &bytes) }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Appends one byte of JSON, or its `\u00XX` escape if it's one `scriptSafe` rewrites.
    ///
    /// - Parameters:
    ///   - byte: The byte.
    ///   - bytes: The output to append to.
    private static func appendScriptSafe(_ byte: UInt8, to bytes: inout [UInt8]) {
        switch byte {
        case UInt8(ascii: "&"), UInt8(ascii: "<"), UInt8(ascii: ">"): bytes += scriptEscapes[byte] ?? []
        default: bytes.append(byte)
        }
    }

    /// The JSON escape for each byte `scriptSafe` rewrites: a backslash, `u00`, and the byte in hexadecimal.
    private static let scriptEscapes: [UInt8: [UInt8]] = [("&", "26"), ("<", "3c"), (">", "3e")]
        .reduce(into: [:]) { (table, pair: (character: Unicode.Scalar, hex: String)) in
            table[UInt8(ascii: pair.character)] = Array(("\\" + "u00" + pair.hex).utf8)
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
