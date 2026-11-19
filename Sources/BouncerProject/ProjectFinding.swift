import BouncerCore

/// Builds project findings, which name a repo-relative path rather than a file URL.
enum ProjectFinding {
    /// Builds a finding.
    ///
    /// - Parameters:
    ///   - ruleID: The rule.
    ///   - path: The repo-relative path the finding lands in.
    ///   - line: The 1-indexed line.
    ///   - message: The explanation.
    ///   - context: Repo-wide state, for the repo root and the rule's severity.
    /// - Returns: The finding.
    static func make(
        _ ruleID: String, _ path: String, _ line: Int, _ message: String, _ context: AnalysisContext
    ) -> Finding {
        Finding(
            ruleID: ruleID, severity: context.settings(for: ruleID).severity,
            filePath: RepoPath.url(path, in: context.repoRoot), line: line, message: message
        )
    }

    /// Where to report a problem with a whole node: its first file, at its first import if it has one.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - index: The project's dependency graph.
    /// - Returns: The path and line, or `nil` for a node with no files.
    static func location(of node: String, in index: ProjectIndex) -> (path: String, line: Int)? {
        guard let path = index.filesOfNode[node]?.first else { return nil }
        let line = index.edges.filter { $0.file == path }.map(\.line).min() ?? 1
        return (path, line)
    }

    /// Displays a node: its path, or its Swift target or Go package name.
    ///
    /// - Parameter node: The node identifier.
    /// - Returns: The display name.
    static func display(_ node: String) -> String {
        for prefix in ["swift:", "go:"] where node.hasPrefix(prefix) { return String(node.dropFirst(prefix.count)) }
        return node
    }
}
