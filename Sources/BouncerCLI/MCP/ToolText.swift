import Foundation
import BouncerCore
import BouncerMCP
import BouncerReporting

/// Renders the tools' answers, each within its response budget.
enum ToolText {
    /// The room kept for a later section's heading and footer when an earlier section is sized.
    private static let sectionReserve = 80
    /// The note every `verify` answer carries.
    static let projectRulesNote =
        "Project-wide rules (cycles, duplicates, unused code, change rules) refresh on the next scan."

    /// Summarizes a result: what was scanned, the saved run's reuse, the counts and top rules and files.
    ///
    /// - Parameter snapshot: The result.
    /// - Returns: The lines.
    static func summary(_ snapshot: ResultSnapshot) -> [String] {
        let plan = snapshot.plan
        let directory = RepoPath.relative(plan.rootDirectory, to: plan.repoRoot)
        let scope = plan.changedSince.map { "files changed since \($0) under" } ?? "every file under"
        var lines = ["Scanned \(scope) \(directory.isEmpty ? "." : directory): \(snapshot.files.count) file(s)."]
        lines += snapshot.reuseNote.map { [$0] } ?? []
        lines += ReportSummary.lines(snapshot.result, repoRoot: plan.repoRoot, elapsed: snapshot.duration)
        return lines + ["Next: findings lists them (filter by rule, path, severity); verify re-checks files you edit."]
    }

    /// Renders one page of findings under a reading's opening lines.
    ///
    /// - Parameters:
    ///   - header: The opening lines.
    ///   - page: The findings, offset, and grouping to render.
    ///   - budget: The response budget.
    /// - Returns: The answer.
    static func findings(header: [String], page: FindingsRequest, budget: ResponseBudget) -> String {
        let opening = header.joined(separator: "\n")
        let pager = AgentPager(repoRoot: page.repoRoot, grouping: page.grouping)
        let footer = AgentPageFooter(unfilteredTotal: page.unfilteredTotal)
        let room = budget.maxChars - opening.count - 1
        let rendered = pager.page(page.findings, offset: page.offset, maxChars: room, footer: footer)
        return budget.fit(opening + "\n" + rendered.text).text
    }

    /// Renders a `verify` answer: the counts, then the new findings, then the ones still there.
    ///
    /// - Parameters:
    ///   - header: The opening lines.
    ///   - reanalysis: What re-analyzing the files found.
    ///   - repoRoot: The repository root.
    ///   - budget: The response budget.
    /// - Returns: The answer.
    static func verify(header: [String], _ reanalysis: Reanalysis, repoRoot: URL, budget: ResponseBudget) -> String {
        let delta = reanalysis.delta
        let lines = header + verifyLines(reanalysis.targets, delta: delta)
        let sections = [("New:", delta.new), ("Still there:", delta.remaining)].filter { !$0.1.isEmpty }
        return budget.fit(render(sections, after: lines, pager: AgentPager(repoRoot: repoRoot), budget: budget)).text
    }

    /// The lines a `verify` answer opens with: the counts, any skipped files, and the project rules note.
    ///
    /// - Parameters:
    ///   - targets: The files re-analyzed.
    ///   - delta: How their findings changed.
    /// - Returns: The lines.
    private static func verifyLines(_ targets: VerifyTargets, delta: FindingDelta) -> [String] {
        let count = targets.analyzed.count + targets.removed.count - targets.skipped.count
        var lines = ["Verified \(count) file\(count == 1 ? "" : "s"): \(delta.summary)"]
        if !targets.skipped.isEmpty {
            let skipped = targets.skipped.joined(separator: ", ")
            lines.append("Skipped (excluded or outside the scanned directory): \(skipped).")
        }
        return lines + [projectRulesNote]
    }

    /// Appends titled sections of findings to some lines, each section sized to what's left of the budget.
    ///
    /// - Parameters:
    ///   - sections: Each section's title and findings.
    ///   - lines: The lines before them.
    ///   - pager: Renders the findings.
    ///   - budget: The response budget.
    /// - Returns: The whole answer.
    private static func render(
        _ sections: [(String, [Finding])], after lines: [String], pager: AgentPager, budget: ResponseBudget
    ) -> String {
        var text = lines.joined(separator: "\n")
        for (index, (title, findings)) in sections.enumerated() {
            let reserve = index < sections.count - 1 ? sectionReserve : 0
            let room = budget.maxChars - text.count - title.count - 2 - reserve
            text += "\n\(title)\n\(firstPage(findings, pager: pager, room: room))"
        }
        return text
    }

    /// Renders a `check` answer: what would block the commit, or that nothing does.
    ///
    /// - Parameters:
    ///   - result: The staged check's result.
    ///   - repoRoot: The repository root.
    ///   - budget: The response budget.
    /// - Returns: The answer.
    static func check(_ result: AnalysisResult, repoRoot: URL, budget: ResponseBudget) -> String {
        let blocking = result.findings.filter { $0.severity >= .error }
        let lower = result.findings.count - blocking.count
        guard !blocking.isEmpty else {
            let note = lower == 0 ? "" : " \(lower) finding(s) below the error threshold don't block it."
            return budget.fit("Nothing blocks the commit." + note).text
        }
        let opening = "\(blocking.count) finding(s) at error severity would block the commit:"
        let room = budget.maxChars - opening.count - 1
        return budget.fit(opening + "\n" + firstPage(blocking, pager: AgentPager(repoRoot: repoRoot), room: room)).text
    }

    /// Renders the first page of some findings, without a cursor, since the tool showing them doesn't page.
    ///
    /// - Parameters:
    ///   - findings: The findings.
    ///   - pager: Renders them.
    ///   - room: The most characters the page may take.
    /// - Returns: The page.
    private static func firstPage(_ findings: [Finding], pager: AgentPager, room: Int) -> String {
        let footer = AgentPageFooter(namesCursor: false)
        return pager.page(pager.ordered(findings), offset: 0, maxChars: room, footer: footer).text
    }
}

/// The page a `findings` call asks for.
struct FindingsRequest: Sendable {
    /// The repository root.
    let repoRoot: URL
    /// The matching findings, in page order.
    let findings: [Finding]
    /// Where the page starts.
    let offset: Int
    /// How findings are grouped.
    let grouping: ReportGrouping
    /// How many findings there were before filters, when filters are set.
    let unfilteredTotal: Int?
}
