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
            parameterCount: parameterCount(of: node), returnCount: tally.returns,
            cognitiveComplexity: tally.score, maxNestingDepth: tally.maxDepth
        )
    }

    /// Counts a function's declared parameters, ignoring comments between them.
    ///
    /// - Parameter node: The function node.
    /// - Returns: The parameter count; an arrow function's bare `x => …` parameter counts as one.
    private func parameterCount(of node: Node) -> Int {
        guard let list = node.child(byFieldName: "parameters") else {
            return node.child(byFieldName: "parameter") == nil ? 0 : 1
        }
        let children = (0..<list.namedChildCount).compactMap { list.namedChild(at: $0) }
        return children.filter { $0.nodeType != "comment" }.count
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
        if type == quality.returnNodeType, !depth.inNestedFunction { tally.returns += 1 }
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
    /// - Returns: One plus nesting for a nesting structure or ternary, one for `else` or a new run of
    ///   logical operators, and zero otherwise; an `else if`'s `if` scores nothing, since its `else` did.
    private func increment(for node: Node, type: String, nesting: Int) -> Int {
        if isNestingStructure(node, type: type) || type == quality.ternaryNodeType { return 1 + nesting }
        if type == quality.elseNodeType || startsLogicalRun(node, type: type) { return 1 }
        return 0
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
        } else if spec.functionNodeTypes.contains(type) {
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
        quality.nestingNodeTypes.contains(type) && node.parent?.nodeType != quality.elseNodeType
    }

    /// Reports whether a node starts a new run of logical operators.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - type: Its type.
    /// - Returns: Whether it's a logical operator whose parent isn't the same operator.
    private func startsLogicalRun(_ node: Node, type: String) -> Bool {
        guard type == spec.logicalOperatorNodeType, let op = logicalOperator(of: node) else { return false }
        guard let parent = node.parent, parent.nodeType == type else { return true }
        return logicalOperator(of: parent) != op
    }

    /// Reads a binary node's operator, if it's a logical one.
    ///
    /// - Parameter node: The binary-expression node.
    /// - Returns: `&&`, `||`, or `??`, or `nil` for any other operator.
    private func logicalOperator(of node: Node) -> String? {
        let op = node.child(byFieldName: "operator").flatMap(text)
        return ["&&", "||", "??"].contains(op) ? op : nil
    }
}
