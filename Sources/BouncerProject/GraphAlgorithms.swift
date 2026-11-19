/// Tarjan's algorithm for strongly connected components, run iteratively-safe on project-sized graphs.
enum StronglyConnected {
    /// Splits a directed graph into strongly connected components.
    ///
    /// - Parameter edgesFrom: Each node's outgoing edges.
    /// - Returns: The components; a component of two or more nodes contains a cycle.
    static func components(edgesFrom: [String: [ImportEdge]]) -> [Set<String>] {
        var state = TarjanState()
        let nodes = Set(edgesFrom.keys).union(edgesFrom.values.flatMap { $0.map(\.to) }).sorted()
        for node in nodes where state.index[node] == nil {
            state.visit(node, edgesFrom: edgesFrom)
        }
        return state.components
    }
}

/// Tarjan's bookkeeping: discovery order, low-links, and the working stack.
private struct TarjanState {
    var index: [String: Int] = [:]
    var lowLink: [String: Int] = [:]
    var stack: [String] = []
    var onStack: Set<String> = []
    var components: [Set<String>] = []

    /// Visits a node and everything reachable from it, emitting each component as it closes.
    ///
    /// - Parameters:
    ///   - node: The node to visit.
    ///   - edgesFrom: Each node's outgoing edges.
    mutating func visit(_ node: String, edgesFrom: [String: [ImportEdge]]) {
        index[node] = index.count
        lowLink[node] = index[node]
        stack.append(node)
        onStack.insert(node)
        for next in Set((edgesFrom[node] ?? []).map(\.to)).sorted() { relax(node, next, edgesFrom: edgesFrom) }
        if lowLink[node] == index[node] { popComponent(rootedAt: node) }
    }

    /// Follows one edge, updating the node's low-link.
    ///
    /// - Parameters:
    ///   - node: The current node.
    ///   - next: The edge's target.
    ///   - edgesFrom: Each node's outgoing edges.
    private mutating func relax(_ node: String, _ next: String, edgesFrom: [String: [ImportEdge]]) {
        if index[next] == nil {
            visit(next, edgesFrom: edgesFrom)
            lowLink[node] = min(lowLink[node] ?? 0, lowLink[next] ?? 0)
        } else if onStack.contains(next) {
            lowLink[node] = min(lowLink[node] ?? 0, index[next] ?? 0)
        }
    }

    /// Pops the stack down to a component's root and records the component.
    ///
    /// - Parameter root: The component's root node.
    private mutating func popComponent(rootedAt root: String) {
        var component: Set<String> = []
        while let top = stack.popLast() {
            onStack.remove(top)
            component.insert(top)
            if top == root { break }
        }
        components.append(component)
    }
}

/// Finds a readable cycle path for a message.
enum CyclePath {
    /// Finds the shortest cycle that starts with an edge and returns to its source, inside one component.
    ///
    /// - Parameters:
    ///   - edge: The edge the cycle starts with.
    ///   - component: The cycle's nodes.
    ///   - edgesFrom: Each node's outgoing edges.
    /// - Returns: The node names along the cycle, starting and ending at the edge's source.
    static func shortest(
        from edge: ImportEdge, within component: Set<String>, edgesFrom: [String: [ImportEdge]]
    ) -> [String] {
        let parent = breadthFirstParents(from: edge.to, toward: edge.from, within: component, edgesFrom: edgesFrom)
        var path = [edge.from], current = edge.from
        while current != edge.to, let previous = parent[current] {
            path.append(previous)
            current = previous
        }
        return ([edge.from] + path.reversed()).map(display)
    }

    /// Searches breadth-first from one node until another is reached, recording each node's parent.
    ///
    /// - Parameters:
    ///   - start: Where the search begins.
    ///   - goal: The node to reach.
    ///   - component: The nodes the search may visit.
    ///   - edgesFrom: Each node's outgoing edges.
    /// - Returns: Each reached node's parent on its shortest path from `start`.
    private static func breadthFirstParents(
        from start: String, toward goal: String, within component: Set<String>, edgesFrom: [String: [ImportEdge]]
    ) -> [String: String] {
        var parent: [String: String] = [:], seen: Set<String> = [start], queue = [start]
        while !queue.isEmpty, !seen.contains(goal) {
            let node = queue.removeFirst()
            let fresh = unseenNeighbors(of: node, within: component, seen: seen, edgesFrom: edgesFrom)
            seen.formUnion(fresh)
            queue.append(contentsOf: fresh)
            for next in fresh { parent[next] = node }
        }
        return parent
    }

    /// Lists a node's distinct neighbors inside the component that have not been visited yet.
    ///
    /// - Parameters:
    ///   - node: The node whose edges are followed.
    ///   - component: The nodes the search may visit.
    ///   - seen: The nodes already visited.
    ///   - edgesFrom: Each node's outgoing edges.
    /// - Returns: The unvisited neighbors, sorted.
    private static func unseenNeighbors(
        of node: String, within component: Set<String>, seen: Set<String>, edgesFrom: [String: [ImportEdge]]
    ) -> [String] {
        Set((edgesFrom[node] ?? []).map(\.to)).sorted().filter { component.contains($0) && !seen.contains($0) }
    }

    /// Shortens a node for display by dropping its `swift:` or `go:` prefix.
    ///
    /// - Parameter node: The node identifier.
    /// - Returns: Its display name.
    private static func display(_ node: String) -> String {
        for prefix in ["swift:", "go:"] where node.hasPrefix(prefix) { return String(node.dropFirst(prefix.count)) }
        return node
    }
}
