import Foundation
import BouncerCore

/// One file's findings from one rule: the unit of work `next_batch` hands an agent.
public struct FindingCluster: Sendable, Equatable {
    /// The file's path, relative to the repository root.
    public let path: String
    /// The rule's ID.
    public let ruleID: String
    /// How much work fixing the rule's findings takes.
    public let cost: FixCost
    /// The most severe of the findings.
    public let severity: Severity
    /// The findings, by line.
    public let findings: [Finding]

    /// Groups one file's findings from one rule.
    ///
    /// - Parameters:
    ///   - path: The file's path, relative to the repository root.
    ///   - findings: The findings, all from one rule in that file; at least one.
    ///   - cost: The rule's fix cost.
    init(path: String, findings: [Finding], cost: FixCost) {
        (self.path, self.cost) = (path, cost)
        ruleID = findings.first?.ruleID ?? ""
        severity = findings.map(\.severity).max() ?? .info
        self.findings = findings.sorted { ($0.line, $0.message) < ($1.line, $1.message) }
    }

    /// The file the findings are in.
    public var file: URL? { findings.first?.filePath }
}

/// Picks the cluster an agent should fix next, following the work order and breaking ties the same way every time.
///
/// The work order decides first: quick fixes first puts every mechanical cluster before any refactor, then errors
/// before warnings before info; severity first swaps the two. A cluster's severity is its most severe finding.
/// Ties go to OWASP-tagged rules, then files the agent touched (most recent first), then larger clusters, then
/// path and rule ID. A rule with no fix-cost tag, such as a custom rule, counts as mechanical.
public struct NextBatchRanking: Sendable {
    /// What comes first.
    public enum Order: Sendable {
        /// Every mechanical fix before any refactor; within each, errors before warnings before info.
        case quickFixesFirst
        /// Errors before warnings before info; within each, mechanical before refactor.
        case severityFirst
    }

    /// Looks up a rule's fix cost, or `nil` for an untagged rule.
    public typealias CostLookup = @Sendable (String) -> FixCost?

    /// What comes first.
    private let order: Order
    /// Files the agent touched, repo-relative, most recent first.
    private let touched: [String: Int]
    /// Looks up a rule's fix cost.
    private let cost: CostLookup

    /// Creates a ranking.
    ///
    /// - Parameters:
    ///   - order: What comes first.
    ///   - touched: Files the agent touched, repo-relative, most recent first.
    ///   - cost: Looks up a rule's fix cost; defaults to the built-in tags.
    public init(order: Order, touched: [String] = [], cost: @escaping CostLookup = { FixCost.cost(forRule: $0) }) {
        (self.order, self.cost) = (order, cost)
        self.touched = Dictionary(touched.enumerated().map { ($1, $0) }) { first, _ in first }
    }

    /// Groups findings into one cluster per file and rule, in no particular order.
    ///
    /// - Parameters:
    ///   - findings: The findings.
    ///   - repoRoot: The repository root, which cluster paths are relative to.
    /// - Returns: The clusters.
    public func clusters(_ findings: [Finding], repoRoot: URL) -> [FindingCluster] {
        let grouped = Dictionary(grouping: findings) { ClusterKey(file: $0.filePath.path, rule: $0.ruleID) }
        return grouped.values.compactMap { group in
            guard let first = group.first else { return nil }
            let path = RepoPath.relative(first.filePath, to: repoRoot)
            return FindingCluster(path: path, findings: group, cost: cost(first.ruleID) ?? .mechanical)
        }
    }

    /// Orders clusters, the one to fix first first.
    ///
    /// - Parameter clusters: The clusters.
    /// - Returns: The clusters, ranked.
    public func ranked(_ clusters: [FindingCluster]) -> [FindingCluster] {
        clusters.sorted(by: precedes)
    }

    /// Picks the cluster to fix first among findings, and counts the rest.
    ///
    /// - Parameters:
    ///   - findings: The findings.
    ///   - repoRoot: The repository root, which cluster paths are relative to.
    /// - Returns: The pick, or `nil` when there are no findings.
    public func pick(_ findings: [Finding], repoRoot: URL) -> NextBatchPick? {
        let all = clusters(findings, repoRoot: repoRoot)
        guard let best = all.min(by: precedes) else { return nil }
        return NextBatchPick(cluster: best, clustersLeft: all.count - 1)
    }

    /// Whether one cluster comes before another.
    ///
    /// - Parameters:
    ///   - lhs: One cluster.
    ///   - rhs: The other.
    /// - Returns: Whether `lhs` should be fixed first.
    public func precedes(_ lhs: FindingCluster, _ rhs: FindingCluster) -> Bool {
        let (left, right) = (primary(lhs), primary(rhs))
        if left != right { return left < right }
        let leftTies = (owasp(lhs), touchedRank(lhs), -lhs.findings.count)
        let rightTies = (owasp(rhs), touchedRank(rhs), -rhs.findings.count)
        if leftTies != rightTies { return leftTies < rightTies }
        return (lhs.path, lhs.ruleID) < (rhs.path, rhs.ruleID)
    }

    /// The work order's key: cost and severity, in the order's priority, lower first.
    ///
    /// - Parameter cluster: The cluster.
    /// - Returns: The key.
    private func primary(_ cluster: FindingCluster) -> (Int, Int) {
        let costRank = cluster.cost == .mechanical ? 0 : 1
        let severityRank = [Severity.error, .warning, .info].firstIndex(of: cluster.severity) ?? 0
        return order == .quickFixesFirst ? (costRank, severityRank) : (severityRank, costRank)
    }

    /// 0 for a rule with an OWASP category, 1 otherwise.
    ///
    /// - Parameter cluster: The cluster.
    /// - Returns: The rank.
    private func owasp(_ cluster: FindingCluster) -> Int {
        OWASPCategory.category(forRule: cluster.ruleID) == nil ? 1 : 0
    }

    /// How recently the agent touched the cluster's file: its place in `touched`, or past the end.
    ///
    /// - Parameter cluster: The cluster.
    /// - Returns: The rank, lower first.
    private func touchedRank(_ cluster: FindingCluster) -> Int {
        touched[cluster.path] ?? Int.max
    }
}

/// A file and rule, for grouping findings into clusters.
private struct ClusterKey: Hashable {
    /// The file's full path.
    let file: String
    /// The rule's ID.
    let rule: String
}

/// The cluster to fix next, and how many others are left.
public struct NextBatchPick: Sendable, Equatable {
    /// The cluster.
    public let cluster: FindingCluster
    /// How many other clusters match.
    public let clustersLeft: Int

    /// Records a pick.
    ///
    /// - Parameters:
    ///   - cluster: The cluster.
    ///   - clustersLeft: How many other clusters match.
    public init(cluster: FindingCluster, clustersLeft: Int) {
        (self.cluster, self.clustersLeft) = (cluster, clustersLeft)
    }
}
