import Foundation
import BouncerCore

/// How a grouped report lists its findings: under each file, or under each rule.
public enum ReportGrouping: String, Sendable, CaseIterable {
    /// One heading per file, with its findings as `LINE RULE MESSAGE`.
    case file
    /// One heading per rule, with its findings as `PATH:LINE MESSAGE`.
    case rule
}

/// One heading of a grouped report and the findings listed under it.
public struct FindingGroup: Sendable, Equatable {
    /// The heading: a path relative to the repository root, or a rule ID.
    public let header: String
    /// The group's findings, as rows with relative paths, in the order they were given.
    public let rows: [ReportRow]

    /// Groups findings under their file or rule, keeping each group where its first finding came.
    ///
    /// - Parameters:
    ///   - findings: The findings, already in the order to show them.
    ///   - grouping: Whether to group by file or by rule.
    ///   - repoRoot: The repository root, which paths are shown relative to.
    /// - Returns: The groups, in the order their first findings appear.
    public static func groups(_ findings: [Finding], by grouping: ReportGrouping, repoRoot: URL) -> [FindingGroup] {
        let rows = findings.map { ReportRow($0, repoRoot: repoRoot) }
        let header: (ReportRow) -> String = grouping == .file ? { $0.path } : { $0.ruleID }
        let members = Dictionary(grouping: rows, by: header)
        var seen = Set<String>()
        let order = rows.map(header).filter { seen.insert($0).inserted }
        return order.map { FindingGroup(header: $0, rows: members[$0] ?? []) }
    }
}
