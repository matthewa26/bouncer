import BouncerCore

/// One resolved import between two project nodes, with where it's written.
public struct ImportEdge: Sendable, Equatable {
    public let from: String
    public let to: String
    public let file: String
    public let line: Int
    public let specifier: String
}

/// The project's dependency graph: one node per file (TS/JS, Python), Swift target, or Go package, and
/// an edge for each import that resolves to another node in the project.
public struct ProjectIndex: Sendable {
    public let facts: [String: FileFacts]
    public let edges: [ImportEdge]
    /// Each file's node.
    public let nodeOfFile: [String: String]

    /// Builds the index from every indexed file's facts.
    ///
    /// - Parameters:
    ///   - facts: Every indexed file's facts.
    ///   - resolvers: Resolves each language's imports; files with no resolver are left out.
    public init(facts: [FileFacts], resolvers: ImportResolvers) {
        self.facts = Dictionary(facts.map { ($0.path, $0) }) { first, _ in first }
        nodeOfFile = Dictionary(
            facts.compactMap { fact in resolvers.resolver(for: fact.path).map { (fact.path, $0.node(of: fact.path)) } }
        ) { first, _ in first }
        edges = facts.flatMap { Self.edges(of: $0, resolvers: resolvers) }
    }

    /// Lists a node's outgoing edges, grouped by source node.
    public var edgesFrom: [String: [ImportEdge]] { Dictionary(grouping: edges, by: \.from) }

    /// Resolves one file's imports into edges.
    ///
    /// - Parameters:
    ///   - fact: The file's facts.
    ///   - resolvers: The language resolvers.
    /// - Returns: An edge per import that resolves to a different node in the project.
    private static func edges(of fact: FileFacts, resolvers: ImportResolvers) -> [ImportEdge] {
        guard let resolver = resolvers.resolver(for: fact.path) else { return [] }
        let from = resolver.node(of: fact.path)
        return fact.module.imports.compactMap { item in
            guard let to = resolver.resolve(item.specifier, from: fact.path), to != from else { return nil }
            return ImportEdge(from: from, to: to, file: fact.path, line: item.line, specifier: item.specifier)
        }
    }
}
