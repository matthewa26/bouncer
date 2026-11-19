import Foundation
import BouncerCore

/// One rule over the whole project's dependency graph.
public protocol ProjectRule: Sendable {
    var id: String { get }

    /// Finds this rule's problems.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph.
    ///   - targets: The repo-relative paths being checked; prefer reporting in one of these.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: The findings.
    func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding]
}

/// The project pass's analyzer: builds the dependency graph from every file's facts and runs each rule.
public struct ProjectRules: ProjectAnalyzer {
    private let rules: [ProjectRule]

    /// Creates the analyzer with the built-in project rules.
    public init() {
        rules = [
            ImportCycleRule(), LayerViolationRule(), UnusedExportRule(), HighFanOutRule(), HubModuleRule(),
            UnstableDependencyRule(), MissingTestFileRule()
        ]
    }

    /// Indexes the project and runs every enabled project rule.
    ///
    /// - Parameters:
    ///   - facts: Every indexed file's facts.
    ///   - targets: The repo-relative paths being checked.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The combined findings.
    public func findings(for facts: [FileFacts], targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let resolvers = ImportResolvers(paths: Set(facts.map(\.path)), repoRoot: context.repoRoot)
        let index = ProjectIndex(facts: facts, resolvers: resolvers)
        return rules.filter { context.settings(for: $0.id).enabled }
            .flatMap { $0.evaluate(index, targets: targets, context: context) }
    }
}

/// Flags each cycle in the dependency graph once, at an import inside it.
public struct ImportCycleRule: ProjectRule {
    public let id = "import-cycle"

    /// Creates the rule.
    public init() {}

    /// Finds every cycle (strongly connected group of two or more nodes) and reports it once.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph.
    ///   - targets: The paths being checked; a cycle through one is reported in it.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per cycle.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let severity = context.settings(for: id).severity
        let edgesFrom = index.edgesFrom
        return StronglyConnected.components(edgesFrom: edgesFrom).filter { $0.count > 1 }.compactMap { component in
            reportingEdge(in: component, edgesFrom: edgesFrom, targets: targets).map { edge in
                finding(at: edge, within: component, edgesFrom: edgesFrom, severity: severity, context: context)
            }
        }
    }

    /// Builds the finding for one cycle, naming its shortest path through the reported import.
    ///
    /// - Parameters:
    ///   - edge: The import the cycle is reported at.
    ///   - component: The cycle's nodes.
    ///   - edgesFrom: Each node's outgoing edges.
    ///   - severity: The rule's resolved severity.
    ///   - context: Repo-wide state, for the repository root.
    /// - Returns: The cycle's finding.
    private func finding(
        at edge: ImportEdge, within component: Set<String>, edgesFrom: [String: [ImportEdge]],
        severity: Severity, context: AnalysisContext
    ) -> Finding {
        let path = CyclePath.shortest(from: edge, within: component, edgesFrom: edgesFrom)
        let message = "Import cycle: " + path.joined(separator: " → ") + "."
        return Finding(ruleID: id, severity: severity, filePath: RepoPath.url(edge.file, in: context.repoRoot),
                       line: edge.line, message: message)
    }

    /// Picks the import to report a cycle at: one written in a target file if possible, else the first by path.
    ///
    /// - Parameters:
    ///   - component: The cycle's nodes.
    ///   - edgesFrom: Each node's outgoing edges.
    ///   - targets: The paths being checked.
    /// - Returns: The chosen edge.
    private func reportingEdge(
        in component: Set<String>, edgesFrom: [String: [ImportEdge]], targets: Set<String>
    ) -> ImportEdge? {
        let inside = component.flatMap { edgesFrom[$0] ?? [] }.filter { component.contains($0.to) }
            .sorted { ($0.file, $0.line) < ($1.file, $1.line) }
        return inside.first { targets.contains($0.file) } ?? inside.first
    }
}
