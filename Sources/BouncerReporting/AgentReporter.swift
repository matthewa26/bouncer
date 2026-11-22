import Foundation
import BouncerCore

/// Renders an `AnalysisResult` in as few tokens as a coding agent can still act on.
///
/// Findings are grouped under a file (or rule) header with paths relative to the repository root, one plain
/// line each: `LINE RULE MESSAGE` under a file, `PATH:LINE MESSAGE` under a rule. A rule's message is left
/// out when it repeats the last one printed for that rule. There are no JSON keys and no color, and a
/// one-line footer gives the count shown, the count matching, and the flag that fetches the next page.
public struct AgentReporter: Reporter {
    /// The repository root, which paths are shown relative to.
    private let repoRoot: URL
    /// Whether findings go under file or rule headers.
    private let grouping: ReportGrouping
    /// The selection the rendered findings are a page of, for the footer, or `nil` for an unpaged result.
    private let selection: SelectedFindings?

    /// Creates an agent reporter.
    ///
    /// - Parameters:
    ///   - repoRoot: The repository root, which paths are shown relative to.
    ///   - grouping: Whether findings go under file or rule headers.
    ///   - selection: The selection the rendered findings are a page of, or `nil` when they're all of them.
    public init(repoRoot: URL, grouping: ReportGrouping = .file, selection: SelectedFindings? = nil) {
        self.repoRoot = repoRoot
        self.grouping = grouping
        self.selection = selection
    }

    /// Renders a result's findings, grouped, then the footer. Every verbosity renders the same way.
    ///
    /// - Parameters:
    ///   - result: The analysis result, or the page of one, to render.
    ///   - verbosity: Ignored: the format is already as small as it gets.
    /// - Returns: The rendered report.
    public func report(_ result: AnalysisResult, verbosity: OutputVerbosity) -> String {
        let findings = FindingSelection.sorted(result.findings, repoRoot: repoRoot)
        var lastMessages: [String: String] = [:]
        let body = FindingGroup.groups(findings, by: grouping, repoRoot: repoRoot).flatMap { group in
            [group.header] + group.rows.map { "  " + line(for: $0, lastMessages: &lastMessages) }
        }
        return (body + [Self.footer(selection ?? SelectedFindings(all: result))]).joined(separator: "\n")
    }

    /// Renders one finding under its group's header, dropping a message its rule just printed.
    ///
    /// - Parameters:
    ///   - row: The finding.
    ///   - lastMessages: The last message printed for each rule, updated with this one.
    /// - Returns: `LINE RULE MESSAGE` under a file, or `PATH:LINE MESSAGE` under a rule.
    private func line(for row: ReportRow, lastMessages: inout [String: String]) -> String {
        let message = row.message.replacingOccurrences(of: "\n", with: " ")
        let repeated = lastMessages[row.ruleID] == message
        lastMessages[row.ruleID] = message
        let location = grouping == .file ? "\(row.line) \(row.ruleID)" : row.location
        return repeated ? location : "\(location) \(message)"
    }

    /// The report's last line: how many findings are shown out of how many, and how to get the next page.
    ///
    /// - Parameter selection: The selection the report shows.
    /// - Returns: A line such as `Showing 1-20 of 2530 findings (51834 before filters). Next: --offset 20`.
    static func footer(_ selection: SelectedFindings) -> String {
        var text = shown(selection)
        let matching = selection.matching.findings.count
        if selection.totalCount != matching { text += " (\(selection.totalCount) before filters)" }
        text += "."
        if let next = selection.nextOffset { text += " Next: --offset \(next)" }
        return text
    }

    /// Describes which of the matching findings are shown.
    ///
    /// - Parameter selection: The selection the report shows.
    /// - Returns: `12 findings` when they all are, or the shown range out of the matching count.
    private static func shown(_ selection: SelectedFindings) -> String {
        let shown = selection.page.findings.count
        let matching = selection.matching.findings.count
        if shown == matching { return counted(matching) }
        if shown == 0 { return "None of \(matching) findings at offset \(selection.offset)" }
        return "Showing \(selection.offset + 1)-\(selection.offset + shown) of \(matching) findings"
    }

    /// Names a count of findings.
    ///
    /// - Parameter count: How many findings.
    /// - Returns: `No findings`, `1 finding`, or `12 findings`.
    private static func counted(_ count: Int) -> String {
        if count == 0 { return "No findings" }
        return count == 1 ? "1 finding" : "\(count) findings"
    }
}
