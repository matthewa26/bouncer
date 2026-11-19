import Foundation
import BouncerCore

/// Flags a node with more distinct project dependencies than allowed.
public struct HighFanOutRule: ProjectRule {
    public let id = "high-fan-out"

    /// Creates the rule.
    public init() {}

    /// Flags each node depending on more than `maxDependencies` other project nodes.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph.
    ///   - targets: Unused; each finding lands in the over-coupled node's own file.
    ///   - context: Repo-wide state, including the `maxDependencies` parameter.
    /// - Returns: One finding per over-coupled node.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let limit = context.settings(for: id).parameters.int("maxDependencies", default: 15)
        return index.dependencies.filter { $0.value.count > limit }.keys.sorted().compactMap { node in
            ProjectFinding.location(of: node, in: index).map { place in
                let message = Self.message(node, count: index.dependencies[node]?.count ?? 0, limit: limit)
                return ProjectFinding.make(id, place.path, place.line, message, context)
            }
        }
    }

    /// Explains an over-coupled node.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - count: How many project nodes it depends on.
    ///   - limit: The allowed maximum.
    /// - Returns: The finding's message.
    private static func message(_ node: String, count: Int, limit: Int) -> String {
        "\(ProjectFinding.display(node)) depends on \(count) project modules, over the \(limit) limit."
    }
}

/// Flags a node that more of the project depends on than allowed: a hub every change ripples through.
public struct HubModuleRule: ProjectRule {
    public let id = "hub-module"

    /// Creates the rule.
    public init() {}

    /// Flags each node with more than `maxDependents` dependents.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph.
    ///   - targets: Unused; each finding lands in the hub's own file.
    ///   - context: Repo-wide state, including the `maxDependents` parameter.
    /// - Returns: One finding per hub.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let limit = context.settings(for: id).parameters.int("maxDependents", default: 30)
        return index.dependents.filter { $0.value.count > limit }.keys.sorted().compactMap { node in
            ProjectFinding.location(of: node, in: index).map { place in
                let message = Self.message(node, count: index.dependents[node]?.count ?? 0, limit: limit)
                return ProjectFinding.make(id, place.path, place.line, message, context)
            }
        }
    }

    /// Explains a hub node.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - count: How many dependents it has.
    ///   - limit: The allowed maximum.
    /// - Returns: The finding's message.
    private static func message(_ node: String, count: Int, limit: Int) -> String {
        "\(ProjectFinding.display(node)) has \(count) dependents, over the \(limit) limit; "
            + "split it so changes ripple less widely."
    }
}

/// Flags an import from a stable node to a less stable one (the Stable Dependencies Principle).
///
/// A node's instability is `outgoing / (incoming + outgoing)`: 0 when it's depended on and depends on
/// nothing, 1 when it depends on others and nothing depends on it. Stable code should depend on code at
/// least as stable as itself, or changes to the volatile code ripple into everything that's stable.
public struct UnstableDependencyRule: ProjectRule {
    public let id = "unstable-dependency"

    /// Creates the rule.
    public init() {}

    /// Flags each edge whose target is more unstable than its source by more than `minDifference` percent.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph.
    ///   - targets: Unused; each finding lands at the import.
    ///   - context: Repo-wide state, including the `minDifference` parameter (a percentage).
    /// - Returns: One finding per unstable import.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let margin = Double(context.settings(for: id).parameters.int("minDifference", default: 30)) / 100
        let instability = Self.instability(index)
        return index.edges.compactMap { edge in
            guard let from = instability[edge.from], let to = instability[edge.to],
                  to - from > margin else { return nil }
            let message = Self.message(edge, from: from, to: to)
            return ProjectFinding.make(id, edge.file, edge.line, message, context)
        }
    }

    /// Explains an import from a stable node to a less stable one.
    ///
    /// - Parameters:
    ///   - edge: The import.
    ///   - from: The importing node's instability.
    ///   - to: The imported node's instability.
    /// - Returns: The finding's message.
    private static func message(_ edge: ImportEdge, from: Double, to: Double) -> String {
        String(
            format: "%@ (instability %.2f) depends on %@ (instability %.2f); "
                + "depend on something at least as stable.",
            ProjectFinding.display(edge.from), from, ProjectFinding.display(edge.to), to
        )
    }

    /// Computes every connected node's instability.
    ///
    /// - Parameter index: The project's dependency graph.
    /// - Returns: Each node's instability, from 0 (stable) to 1 (unstable).
    static func instability(_ index: ProjectIndex) -> [String: Double] {
        let outgoing = index.dependencies, incoming = index.dependents
        let nodes = Set(outgoing.keys).union(incoming.keys)
        return Dictionary(uniqueKeysWithValues: nodes.map { node in
            let ce = Double(outgoing[node]?.count ?? 0), ca = Double(incoming[node]?.count ?? 0)
            return (node, ce / (ca + ce))
        })
    }
}

/// Flags an import that breaks a declared layer order, such as a core layer importing a UI layer.
///
/// `layers` lists path globs from the top layer down; a file may import its own layer or any later one,
/// never an earlier one. Files matching no layer are unconstrained.
public struct LayerViolationRule: ProjectRule {
    public let id = "layer-violation"

    /// Creates the rule.
    public init() {}

    /// Flags each import from a lower layer into a higher one.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph.
    ///   - targets: Unused; each finding lands at the import.
    ///   - context: Repo-wide state, including the `layers` parameter.
    /// - Returns: One finding per violating import.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let layers = context.settings(for: id).parameters.stringList("layers", default: [])
        guard !layers.isEmpty else { return [] }
        let files = index.filesOfNode
        return index.edges.compactMap { edge in
            guard let from = Self.layer(of: edge.file, layers), let targetFile = files[edge.to]?.first,
                  let to = Self.layer(of: targetFile, layers), to < from else { return nil }
            let message = Self.message(edge, from: layers[from], to: layers[to])
            return ProjectFinding.make(id, edge.file, edge.line, message, context)
        }
    }

    /// Explains an import from a lower layer into a higher one.
    ///
    /// - Parameters:
    ///   - edge: The import.
    ///   - from: The importing file's layer glob.
    ///   - to: The imported file's layer glob.
    /// - Returns: The finding's message.
    private static func message(_ edge: ImportEdge, from: String, to: String) -> String {
        "\(edge.file) (layer \(from)) imports \(ProjectFinding.display(edge.to)) "
            + "(layer \(to)); lower layers must not depend on higher ones."
    }

    /// Finds the first layer whose glob matches a path.
    ///
    /// - Parameters:
    ///   - path: A repo-relative path.
    ///   - layers: The layer globs, top layer first.
    /// - Returns: The layer's position, or `nil` if no layer matches.
    private static func layer(of path: String, _ layers: [String]) -> Int? {
        layers.firstIndex { GlobMatcher.matches(path: path, pattern: $0) }
    }
}
