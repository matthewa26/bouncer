import SwiftTreeSitter
import BouncerRules

/// Measures functions and finds single-location smells in a tree-sitter parse tree.
///
/// The tree-sitter counterpart of `SwiftFunctionMetricsCollector` and
/// `SwiftMarkerCollector`, driven entirely by a language's `TreeSitterQualitySpec`.
struct TreeSitterQualityCollector {
    let spec: TreeSitterLanguageSpec
    let quality: TreeSitterQualitySpec
    let text: (Node) -> String?

    /// Running totals for one function's walk.
    private struct Tally {
        var score = 0
        var returns = 0
        var maxDepth = 0
    }

    /// The walk position: how deeply nested the current node is, and in what.
    private struct Depth {
        var nesting = 0
        var control = 0
        var inNestedFunction = false
    }

    /// Measures one function.
    ///
    /// - Parameters:
    ///   - node: The function node, for its parameters.
    ///   - body: Its body.
    /// - Returns: The function's measurements.
    func metrics(of node: Node, body: Node) -> FunctionMetrics {
        var tally = Tally()
        walkChildren(of: body, depth: Depth(), tally: &tally)
        return FunctionMetrics(
            parameterCount: weight(of: parameters(of: node)), booleanParameterCount: flagCount(of: node),
            returnCount: tally.returns, cognitiveComplexity: tally.score, maxNestingDepth: tally.maxDepth
        )
    }

    /// Lists a function's declared parameters, skipping comments, separators, and receivers like `self`.
    ///
    /// - Parameter node: The function node.
    /// - Returns: The parameter nodes; an arrow function's bare `x => …` parameter is the one entry.
    private func parameters(of node: Node) -> [Node] {
        guard let list = node.child(byFieldName: "parameters") else {
            return node.child(byFieldName: "parameter").map { [$0] } ?? []
        }
        let spec = quality.parameters
        let children = (0..<list.namedChildCount).compactMap { list.namedChild(at: $0) }
        return children.filter { !spec.ignoredNodeTypes.contains($0.nodeType ?? "") }
            .filter { !spec.receiverNames.contains(text($0) ?? "") }
    }

    /// Counts the parameters in a list of parameter nodes, where one Go node can declare several names.
    ///
    /// - Parameter parameters: Parameter nodes.
    /// - Returns: How many parameters they declare.
    private func weight(of parameters: [Node]) -> Int {
        guard let nameType = quality.parameters.groupedNameNodeType else { return parameters.count }
        return parameters.map { parameter in
            max(1, (0..<parameter.namedChildCount).filter { parameter.namedChild(at: $0)?.nodeType == nameType }.count)
        }.reduce(0, +)
    }

    /// Counts a function's boolean flag parameters; an initializer has none, since storing a flag
    /// isn't branching on it.
    ///
    /// - Parameter node: The function node.
    /// - Returns: The flag parameter count.
    private func flagCount(of node: Node) -> Int {
        let name = node.child(byFieldName: "name").flatMap(text) ?? ""
        return quality.initializerNames.contains(name) ? 0 : weight(of: parameters(of: node).filter(isBooleanFlag))
    }

    /// Reports whether a parameter is a boolean flag, by its type annotation or a `true`/`false` default.
    ///
    /// - Parameter parameter: The parameter node.
    /// - Returns: Whether it's a boolean flag.
    private func isBooleanFlag(_ parameter: Node) -> Bool {
        let spec = quality.parameters
        let type = parameter.child(byFieldName: spec.booleanTypeField).flatMap(text)?.filter { $0 != " " }
        if type == spec.booleanTypeText.filter({ $0 != " " }) { return true }
        let defaults = spec.defaultFields.compactMap { parameter.child(byFieldName: $0)?.nodeType }
        return defaults.contains { spec.booleanLiteralNodeTypes.contains($0) }
    }

    /// Walks every child of a node at a given depth.
    ///
    /// - Parameters:
    ///   - node: The parent node.
    ///   - depth: The children's depth.
    ///   - tally: The running totals.
    private func walkChildren(of node: Node, depth: Depth, tally: inout Tally) {
        for index in 0..<node.childCount {
            guard let child = node.child(at: index) else { continue }
            walk(child, depth: depth, tally: &tally)
        }
    }

    /// Scores one node, then walks its children at the depth it establishes.
    ///
    /// - Parameters:
    ///   - node: The node to score.
    ///   - depth: The node's own depth.
    ///   - tally: The running totals.
    private func walk(_ node: Node, depth: Depth, tally: inout Tally) {
        guard let type = node.nodeType else { return }
        tally.score += increment(for: node, type: type, nesting: depth.nesting)
        if type == quality.complexity.returnNodeType, !depth.inNestedFunction { tally.returns += 1 }
        let childDepth = nestedDepth(below: node, type: type, from: depth)
        tally.maxDepth = max(tally.maxDepth, childDepth.control)
        walkChildren(of: node, depth: childDepth, tally: &tally)
    }

    /// The cognitive-complexity increment one node contributes.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - type: Its type.
    ///   - nesting: Its nesting level.
    /// - Returns: One plus nesting for a nesting structure or ternary, plus one for each `else` (a clause,
    ///   or Go's `alternative` field) or new run of logical operators; an `else if`'s own `if` adds nothing
    ///   for itself, since its `else` already did.
    private func increment(for node: Node, type: String, nesting: Int) -> Int {
        let spec = quality.complexity
        var score = isNestingStructure(node, type: type) || type == spec.ternaryNodeType ? 1 + nesting : 0
        if spec.elseNodeTypes.contains(type) || startsLogicalRun(node, type: type) { score += 1 }
        if let field = spec.alternativeField, spec.nestingNodeTypes.contains(type),
           node.child(byFieldName: field) != nil { score += 1 }
        return score
    }

    /// Computes the depth a node's children sit at.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - type: Its type.
    ///   - depth: The node's own depth.
    /// - Returns: One level deeper for a nesting structure or nested function, otherwise unchanged.
    private func nestedDepth(below node: Node, type: String, from depth: Depth) -> Depth {
        var next = depth
        if isNestingStructure(node, type: type) {
            next.nesting += 1
            next.control += 1
        } else if spec.functionNodeTypes.contains(type) || quality.complexity.closureNodeTypes.contains(type) {
            next.nesting += 1
            next.inNestedFunction = true
        }
        return next
    }

    /// Reports whether a node opens a nesting structure, excluding an `else if`'s `if`.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - type: Its type.
    /// - Returns: Whether it scores with a nesting penalty and deepens nesting.
    private func isNestingStructure(_ node: Node, type: String) -> Bool {
        let spec = quality.complexity
        return spec.nestingNodeTypes.contains(type) && !spec.elseIfParentTypes.contains(node.parent?.nodeType ?? "")
    }

    /// Reports whether a node starts a new run of logical operators.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - type: Its type.
    /// - Returns: Whether it's a logical operator whose parent isn't the same operator.
    private func startsLogicalRun(_ node: Node, type: String) -> Bool {
        guard type == quality.complexity.logicalNodeType, let op = logicalOperator(of: node) else { return false }
        guard let parent = node.parent, parent.nodeType == type else { return true }
        return logicalOperator(of: parent) != op
    }

    /// Reads a binary node's operator, if it's a logical one.
    ///
    /// - Parameter node: The binary-expression node.
    /// - Returns: The operator if it's one of the language's logical operators, otherwise `nil`.
    private func logicalOperator(of node: Node) -> String? {
        let op = node.child(byFieldName: "operator").flatMap(text)
        return op.flatMap { quality.complexity.logicalOperators.contains($0) ? $0 : nil }
    }
}
