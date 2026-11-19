import Foundation
import BouncerCore
import BouncerGit

/// Flags a file nearly all of whose recent commits come from one person: if they leave, nobody knows it
/// (a bus factor of 1). Off unless configured, since in a one-person repository every file qualifies.
///
/// Over the last `sinceDays` days, a code file with at least `minCommits` commits is reported when one
/// author made at least `minShare` of them. Authors are told apart by email as `.mailmap` maps it,
/// ignoring case. Nothing is reported when the window has fewer than two authors.
public struct SingleAuthorRule: HistoryRule {
    public let id = "single-author-file"

    /// Creates the rule.
    public init() {}

    /// Runs only when listed under `rules`.
    ///
    /// - Parameter context: Repo-wide state.
    /// - Returns: Whether the rule is configured and enabled.
    public func isEnabled(in context: AnalysisContext) -> Bool {
        context.ruleSettings[id]?.enabled == true
    }

    /// Reads `sinceDays`.
    ///
    /// - Parameter context: Repo-wide state.
    /// - Returns: The window's length, 365 days by default.
    public func days(in context: AnalysisContext) -> Int {
        context.settings(for: id).parameters.int("sinceDays", default: 365)
    }

    /// Flags each checked code file dominated by one author.
    ///
    /// - Parameters:
    ///   - log: The commits read.
    ///   - index: Unused; authorship doesn't depend on imports.
    ///   - targets: The paths being checked.
    ///   - context: Repo-wide state, with `minCommits` and `minShare`.
    /// - Returns: One finding per single-author file.
    public func evaluate(
        _ log: ChangeLog, index: ProjectIndex, targets: Set<String>, context: AnalysisContext
    ) -> [Finding] {
        let window = log.within(days: days(in: context))
        guard Set(window.map(\.author)).count >= 2 else { return [] }
        let parameters = context.settings(for: id).parameters
        let minCommits = parameters.int("minCommits", default: 5)
        let minShare = parameters.double("minShare", default: 0.9)
        let byPath = ChangeLog.commitsByPath(window) { targets.contains($0) && SourceCode.isCode($0) }
        return byPath.filter { $0.value.count >= minCommits }.sorted { $0.key < $1.key }.compactMap { path, commits in
            finding(path, commits: commits, minShare: minShare, context: context)
        }
    }

    /// Builds a file's finding if its top author's share reaches `minShare`.
    ///
    /// - Parameters:
    ///   - path: The repo-relative path.
    ///   - commits: The commits that touched it.
    ///   - minShare: The share that counts as one person's file.
    ///   - context: Repo-wide state.
    /// - Returns: The finding, or `nil` if authorship is spread out.
    private func finding(
        _ path: String, commits: [GitCommit], minShare: Double, context: AnalysisContext
    ) -> Finding? {
        let byAuthor = Dictionary(grouping: commits, by: \.author).mapValues(\.count)
        guard let top = byAuthor.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }) else { return nil }
        let (author, count) = (top.key, top.value), share = Double(top.value) / Double(commits.count)
        guard share >= minShare else { return nil }
        let message = "\(count) of \(commits.count) commits (\(Int((share * 100).rounded()))%) in the last "
            + "\(days(in: context)) days are by \(author); if they leave, nobody else knows this file (bus factor 1)."
        return ProjectFinding.make(id, path, 1, message, context)
    }
}
