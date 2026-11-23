import Foundation
import BouncerCore

/// Cuts `--format agent` output into pages that fit a character budget, for a server answering an agent.
///
/// Only a bounded number of findings past the offset is rendered, sized from the budget, so a page of a
/// two-million-finding result costs as much as a page of a small one. Pages are cut from the order findings are
/// rendered in, so a page's last shown finding is exactly the one before the next page's first.
public struct AgentPager: Sendable {
    /// The fewest characters a rendered finding takes, with its newline: what sizes the rendered candidates.
    private static let minimumRowChars = 6
    /// What a finding row starts with, under its group's header.
    private static let rowIndent = "  "

    /// The repository root, which paths are shown relative to.
    private let repoRoot: URL
    /// Whether findings go under file or rule headers.
    private let grouping: ReportGrouping

    /// Creates a pager.
    ///
    /// - Parameters:
    ///   - repoRoot: The repository root, which paths are shown relative to.
    ///   - grouping: Whether findings go under file or rule headers.
    public init(repoRoot: URL, grouping: ReportGrouping = .file) {
        self.repoRoot = repoRoot
        self.grouping = grouping
    }

    /// Orders findings the way pages are cut and rendered: by file, line, and rule, or by rule first under
    /// rule headers.
    ///
    /// - Parameter findings: The findings.
    /// - Returns: The ordered findings.
    public func ordered(_ findings: [Finding]) -> [Finding] {
        let byFile = FindingSelection.sorted(findings, repoRoot: repoRoot)
        guard grouping == .rule else { return byFile }
        return byFile.enumerated().sorted { ($0.element.ruleID, $0.offset) < ($1.element.ruleID, $1.offset) }
            .map(\.element)
    }

    /// Renders the page of findings starting at an offset that fits a budget, footer included.
    ///
    /// - Parameters:
    ///   - findings: The matching findings, already in `ordered(_:)` order.
    ///   - offset: Where the page starts.
    ///   - maxChars: The most characters the page may take.
    ///   - footer: How the footer counts the findings and names the next page.
    /// - Returns: The page.
    public func page(
        _ findings: [Finding], offset: Int, maxChars: Int, footer: AgentPageFooter = .init()
    ) -> AgentPage {
        let start = min(max(0, offset), findings.count)
        let end = min(findings.count, start + maxChars / Self.minimumRowChars + 1)
        let reserved = footer.longest(total: findings.count).count + 1
        let (lines, shown) = Self.take(bodyLines(Array(findings[start..<end])), within: maxChars - reserved)
        let page = AgentPage(offset: start, shown: shown, total: findings.count)
        return AgentPage(page, text: (lines + [footer.line(for: page)]).joined(separator: "\n"))
    }

    /// Renders findings as agent lines without the reporter's footer, keeping their order.
    ///
    /// - Parameter findings: The findings, in `ordered(_:)` order.
    /// - Returns: Header and row lines.
    private func bodyLines(_ findings: [Finding]) -> [String] {
        guard grouping == .rule else { return render(findings) }
        var runs: [[Finding]] = []
        for finding in findings {
            guard runs.last?.last?.ruleID == finding.ruleID else { runs.append([finding]); continue }
            runs[runs.count - 1].append(finding)
        }
        return runs.flatMap(render)
    }

    /// Renders findings with `AgentReporter`, dropping its footer.
    ///
    /// - Parameter findings: The findings.
    /// - Returns: The lines.
    private func render(_ findings: [Finding]) -> [String] {
        guard !findings.isEmpty else { return [] }
        let reporter = AgentReporter(repoRoot: repoRoot, grouping: grouping)
        let text = reporter.report(AnalysisResult(findings: findings, coverage: nil), verbosity: .normal)
        return text.components(separatedBy: "\n").dropLast()
    }

    /// Keeps the leading lines that fit a budget, never ending on a header with no rows under it.
    ///
    /// - Parameters:
    ///   - lines: Header and row lines.
    ///   - limit: The most characters the kept lines may take, a newline after each.
    /// - Returns: The kept lines, and how many of them are finding rows.
    private static func take(_ lines: [String], within limit: Int) -> (lines: [String], rows: Int) {
        var kept: [String] = [], used = 0
        for line in lines {
            used += line.count + 1
            if used > limit { break }
            kept.append(line)
        }
        while let last = kept.last, !last.hasPrefix(rowIndent) { kept.removeLast() }
        return (kept, kept.filter { $0.hasPrefix(rowIndent) }.count)
    }
}

/// One page of agent output.
public struct AgentPage: Sendable, Equatable {
    /// Where the page starts among the matching findings.
    public let offset: Int
    /// How many findings it shows.
    public let shown: Int
    /// How many findings match.
    public let total: Int
    /// The rendered page, footer included.
    public let text: String

    /// Records a page's counts, before it's rendered.
    ///
    /// - Parameters:
    ///   - offset: Where the page starts.
    ///   - shown: How many findings it shows.
    ///   - total: How many findings match.
    init(offset: Int, shown: Int, total: Int) {
        (self.offset, self.shown, self.total, self.text) = (offset, shown, total, "")
    }

    /// Attaches the rendered text to a page's counts.
    ///
    /// - Parameters:
    ///   - page: The counts.
    ///   - text: The rendered page.
    init(_ page: AgentPage, text: String) {
        (offset, shown, total, self.text) = (page.offset, page.shown, page.total, text)
    }

    /// Where the next page starts, or `nil` when this one reaches the end or shows nothing.
    public var nextOffset: Int? {
        let end = offset + shown
        return shown > 0 && end < total ? end : nil
    }
}

/// How a page's last line counts its findings and names the next page.
public struct AgentPageFooter: Sendable, Equatable {
    /// How many findings there were before filters, when filters dropped some.
    public var unfilteredTotal: Int?
    /// Whether to name the cursor that fetches the next page.
    public var namesCursor = true

    /// Creates a footer style.
    ///
    /// - Parameters:
    ///   - unfilteredTotal: How many findings there were before filters, or `nil` when unfiltered.
    ///   - namesCursor: Whether to name the next page's cursor.
    public init(unfilteredTotal: Int? = nil, namesCursor: Bool = true) {
        self.unfilteredTotal = unfilteredTotal
        self.namesCursor = namesCursor
    }

    /// The footer for a page.
    ///
    /// - Parameter page: The page's counts.
    /// - Returns: A line such as `Showing 1-37 of 2530 findings (51834 before filters). Next cursor: f11.`
    public func line(for page: AgentPage) -> String {
        var text = shown(page)
        if let unfilteredTotal, unfilteredTotal != page.total { text += " (\(unfilteredTotal) before filters)" }
        text += "."
        if namesCursor, let next = page.nextOffset { text += " Next cursor: \(FindingCursor.encode(offset: next))." }
        return text
    }

    /// The longest footer any page of so many findings can have, to reserve room for it.
    ///
    /// - Parameter total: How many findings match.
    /// - Returns: The longest footer.
    func longest(total: Int) -> String {
        let big = max(total, unfilteredTotal ?? 0) + 1
        let paged = line(for: AgentPage(offset: big - 1, shown: 1, total: big + 1))
        let empty = line(for: AgentPage(offset: big, shown: 0, total: big))
        return paged.count > empty.count ? paged : empty
    }

    /// Says which of the matching findings the page shows.
    ///
    /// - Parameter page: The page's counts.
    /// - Returns: `12 findings` when it shows all of them, or the range shown out of the total.
    private func shown(_ page: AgentPage) -> String {
        if page.total == 0 { return "No findings" }
        if page.shown == page.total { return page.total == 1 ? "1 finding" : "\(page.total) findings" }
        if page.shown > 0 { return "Showing \(page.offset + 1)-\(page.offset + page.shown) of \(page.total) findings" }
        let why = page.offset >= page.total ? "at this cursor" : "fit; raise max_chars or max_tokens"
        return "None of \(page.total) findings \(why)"
    }
}
