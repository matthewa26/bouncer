import Foundation
import BouncerCore

/// Where the HTML report gets what it shows beyond the findings themselves: each file's text, each rule's
/// rationale and example, and each finding's quick fix. The defaults read the disk and the built-in catalogs;
/// tests pass fakes.
struct HTMLReportLookups: Sendable {
    /// Reads a file as UTF-8 text, or returns `nil` if it can't be read or isn't valid UTF-8.
    var readFile: @Sendable (URL) -> String? = Self.readUTF8
    /// Why a rule matters, by rule ID, or `nil` if the catalog doesn't say.
    var rationale: @Sendable (String) -> String? = RuleCatalog.rationale(for:)
    /// A rule's generic before-and-after example, by rule ID, or `nil` if it has none.
    var example: @Sendable (String) -> RuleExample? = RuleExamples.example(for:)
    /// The exact fix for a finding, given its file's lines (as `SourceFile.lines(of:)` splits them), or `nil` if it
    /// has none.
    var fix: @Sendable (Finding, [String]) -> QuickFix? = QuickFixes.fix(for:lines:)

    /// Reads a file from disk as UTF-8.
    ///
    /// - Parameter url: The file.
    /// - Returns: Its text, or `nil` if it can't be read or isn't valid UTF-8.
    private static func readUTF8(_ url: URL) -> String? {
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
