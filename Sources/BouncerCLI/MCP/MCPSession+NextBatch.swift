import Foundation
import BouncerCore
import BouncerConfig
import BouncerMCP
import BouncerReporting

extension MCPSession {
    /// Answers `next_batch`: the one file and rule to fix next, with the code around each finding.
    ///
    /// - Parameter arguments: `rule`, `path`, `severity`, and the budget.
    /// - Returns: The cluster, or that nothing matches.
    /// - Throws: `ToolError` for bad arguments or when there's no result.
    func nextBatch(_ arguments: ToolArguments) async throws -> MCPAnswer {
        let selection = try arguments.selection()
        let reading = try await reading()
        let (snapshot, root) = (reading.snapshot, defaults.repoRoot)
        let all = snapshot.result.findings
        let matching = selection.isActive ? selection.filtering(all, repoRoot: root) : all
        let ranking = NextBatchRanking(order: snapshot.plan.workOrder, touched: touchedPaths(snapshot))
        let pick = ranking.pick(matching, repoRoot: root)
        let source = pick.map { snapshot.source(of: $0.cluster) }
        return MCPAnswer(ToolText.nextBatch(header: reading.header, pick, source: source, budget: arguments.budget))
    }

    /// The files `next_batch` favors: those verified this session, most recent first, then those the scan's
    /// `changed_since` narrowed it to.
    ///
    /// - Parameter snapshot: The result.
    /// - Returns: Repo-relative paths, most favored first.
    private func touchedPaths(_ snapshot: ResultSnapshot) -> [String] {
        guard snapshot.plan.changedSince != nil else { return verified }
        return verified + snapshot.files.keys.sorted()
    }
}

extension ScanPlan {
    /// What `next_batch` recommends first, from `agent.workOrder`.
    var workOrder: NextBatchRanking.Order {
        (config.agent?.workOrder ?? .quickFixesFirst) == .quickFixesFirst ? .quickFixesFirst : .severityFirst
    }
}

extension ResultSnapshot {
    /// A cluster's file as it is now, without its lines when it changed since it was analyzed.
    ///
    /// - Parameter cluster: The cluster.
    /// - Returns: The source.
    func source(of cluster: FindingCluster) -> NextBatchSource {
        guard let url = cluster.file else { return NextBatchSource(lines: nil) }
        let stamp = files[cluster.path]?.stamp
        if let stamp, FileStamp.read(url) != stamp { return NextBatchSource(lines: nil, changedSinceScan: true) }
        return NextBatchSource.read(url)
    }
}

extension ToolText {
    /// What `next_batch` says when no finding matches.
    private static let nothingLeft = "Nothing left to fix: no findings match."

    /// Renders a `next_batch` answer under a reading's opening lines.
    ///
    /// - Parameters:
    ///   - header: The opening lines.
    ///   - pick: The cluster to fix next, or `nil` when nothing matches.
    ///   - source: Its file as it is now.
    ///   - budget: The response budget.
    /// - Returns: The answer.
    static func nextBatch(
        header: [String], _ pick: NextBatchPick?, source: NextBatchSource?, budget: ResponseBudget
    ) -> String {
        let opening = header.joined(separator: "\n")
        guard let pick, let source else { return budget.fit(opening + "\n" + nothingLeft).text }
        let room = budget.maxChars - opening.count - 1
        return budget.fit(opening + "\n" + NextBatchWriter(maxChars: room).render(pick, source: source)).text
    }
}
