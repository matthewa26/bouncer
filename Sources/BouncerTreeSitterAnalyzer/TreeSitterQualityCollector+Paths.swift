import SwiftTreeSitter
import BouncerRules

/// NPath (Nejmeh's count of acyclic execution paths) and Halstead counts for tree-sitter languages.
///
/// NPath: statements in sequence multiply; an `if` adds its branches' paths plus one per logical operator
/// in its condition (and one for a missing `else`), with each `elif` adding its own; a loop adds one for
/// skipping its body; a `switch` sums its cases, plus one without a `default`; a `try` adds each handler;
/// a ternary adds its other branch. Nested functions count as one path, and every count saturates at
/// `PathCount.cap`.
///
/// Halstead: operands are named leaf nodes (identifiers and literals) plus whole string literals; every
/// other leaf (keywords, punctuation, operators) is an operator, except comments and closing brackets.
extension TreeSitterQualityCollector {
    private static let closingTokens: Set<String> = [")", "]", "}", "comment"]

    /// Counts the paths through a node.
    ///
    /// - Parameters:
    ///   - node: A function body, or any node inside one.
    ///   - flow: The language's flow node types.
    /// - Returns: Its NPath value.
    func paths(through node: Node, flow: FlowSpec) -> Int {
        let type = node.nodeType ?? ""
        if type == flow.ifNodeType { return ifPaths(node, flow: flow) }
        if spec.functionNodeTypes.contains(type) || quality.complexity.closureNodeTypes.contains(type) { return 1 }
        if flow.switchNodeTypes.contains(type) { return switchPaths(node, flow: flow) }
        if flow.tryNodeTypes.contains(type) { return tryPaths(node, flow: flow) }
        let sequence = product(namedChildren(of: node), flow: flow)
        let extra = flow.loopNodeTypes.contains(type) ? 1 + operators(in: node.child(byFieldName: "condition")) : 0
        return PathCount.add(sequence, type == quality.complexity.ternaryNodeType ? 1 : extra)
    }

    /// Multiplies the paths of nodes run one after another.
    ///
    /// - Parameters:
    ///   - nodes: The nodes.
    ///   - flow: The language's flow node types.
    /// - Returns: The product of their paths.
    private func product(_ nodes: [Node], flow: FlowSpec) -> Int {
        nodes.reduce(1) { PathCount.multiply($0, paths(through: $1, flow: flow)) }
    }

    /// Adds up the paths of alternatives.
    ///
    /// - Parameters:
    ///   - nodes: The alternatives.
    ///   - flow: The language's flow node types.
    /// - Returns: The sum of their paths.
    private func sum(_ nodes: [Node], flow: FlowSpec) -> Int {
        nodes.reduce(0) { PathCount.add($0, paths(through: $1, flow: flow)) }
    }

    /// Counts the paths through an `if`, its `elif`s, and its `else`.
    ///
    /// - Parameters:
    ///   - node: The `if` statement.
    ///   - flow: The language's flow node types.
    /// - Returns: Its paths.
    private func ifPaths(_ node: Node, flow: FlowSpec) -> Int {
        let alternatives = (0..<node.childCount).filter { node.fieldNameForChild(at: $0) == "alternative" }
            .compactMap { node.child(at: $0) }
        let branches = [node] + alternatives.filter { $0.nodeType == flow.elifNodeType }
        let others = alternatives.filter { $0.nodeType != flow.elifNodeType }
        let taken = branches.reduce(0) { PathCount.add($0, branchPaths($1, flow: flow)) }
        return PathCount.add(taken, others.isEmpty ? 1 : sum(others, flow: flow))
    }

    /// Counts the paths through one `if` or `elif` branch: its body's, plus one per logical operator in its
    /// condition.
    ///
    /// - Parameters:
    ///   - branch: The `if` statement or `elif` clause.
    ///   - flow: The language's flow node types.
    /// - Returns: Its paths.
    private func branchPaths(_ branch: Node, flow: FlowSpec) -> Int {
        let consequence = branch.child(byFieldName: flow.consequenceField).map { paths(through: $0, flow: flow) } ?? 1
        return consequence + operators(in: branch.child(byFieldName: "condition"))
    }

    /// Counts the paths through a `switch` or `match`: each case, plus one if nothing matches.
    ///
    /// - Parameters:
    ///   - node: The statement.
    ///   - flow: The language's flow node types.
    /// - Returns: Its paths.
    private func switchPaths(_ node: Node, flow: FlowSpec) -> Int {
        let cases = caseNodes(in: node, flow: flow)
        let hasDefault = cases.contains { flow.defaultCaseNodeTypes.contains($0.nodeType ?? "") || isWildcard($0) }
        return PathCount.add(cases.reduce(0) { PathCount.add($0, product(namedChildren(of: $1), flow: flow)) },
                             hasDefault ? 0 : 1)
    }

    /// Reports whether a Python `case` matches anything, as `case _:` does.
    ///
    /// - Parameter node: The case clause.
    /// - Returns: Whether its pattern is `_`.
    private func isWildcard(_ node: Node) -> Bool {
        namedChildren(of: node).first.flatMap(text) == "_"
    }

    /// Finds a `switch`'s cases, looking through wrappers such as `switch_body` but not into nested code.
    ///
    /// - Parameters:
    ///   - node: The statement or a wrapper inside it.
    ///   - flow: The language's flow node types.
    /// - Returns: The case and default clauses.
    private func caseNodes(in node: Node, flow: FlowSpec) -> [Node] {
        namedChildren(of: node).flatMap { child -> [Node] in
            let type = child.nodeType ?? ""
            if flow.caseNodeTypes.contains(type) || flow.defaultCaseNodeTypes.contains(type) { return [child] }
            return flow.caseContainerNodeTypes.contains(type) ? caseNodes(in: child, flow: flow) : []
        }
    }

    /// Counts the paths through a `try`: its body and other clauses in sequence, plus each handler.
    ///
    /// - Parameters:
    ///   - node: The statement.
    ///   - flow: The language's flow node types.
    /// - Returns: Its paths.
    private func tryPaths(_ node: Node, flow: FlowSpec) -> Int {
        let children = namedChildren(of: node)
        let handlers = children.filter { flow.handlerNodeTypes.contains($0.nodeType ?? "") }
        let rest = children.filter { !flow.handlerNodeTypes.contains($0.nodeType ?? "") }
        return PathCount.add(product(rest, flow: flow), sum(handlers, flow: flow))
    }

    /// Counts the logical operators in a condition.
    ///
    /// - Parameter node: The condition, if any.
    /// - Returns: How many `&&`/`||`/`and`/`or` it holds.
    private func operators(in node: Node?) -> Int {
        guard let node else { return 0 }
        let own = logicalOperator(in: node, type: node.nodeType ?? "") ? 1 : 0
        return namedChildren(of: node).reduce(own) { $0 + operators(in: $1) }
    }

    /// Counts a body's Halstead operators and operands.
    ///
    /// - Parameter body: The function's body.
    /// - Returns: Its Halstead counts, or empty counts for a language without a flow spec.
    func halstead(of body: Node) -> HalsteadCounts {
        guard let flow = quality.flow else { return HalsteadCounts() }
        var tokens: HalsteadTokens = ([], [])
        collectTokens(body, flow: flow, into: &tokens)
        return HalsteadCounts.tally(operators: tokens.operators, operands: tokens.operands)
    }

    /// Sorts one node's leaves into operators and operands.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - flow: The language's flow node types.
    ///   - tokens: The operator and operand tokens so far.
    private func collectTokens(_ node: Node, flow: FlowSpec, into tokens: inout HalsteadTokens) {
        let type = node.nodeType ?? "", isAtomic = flow.atomicOperandTypes.contains(type)
        if isAtomic || node.childCount == 0 { record(node, type: type, isAtomic: isAtomic, into: &tokens) }
        guard !isAtomic else { return }
        for child in (0..<node.childCount).compactMap(node.child(at:)) {
            collectTokens(child, flow: flow, into: &tokens)
        }
    }

    /// Records a leaf or atomic literal as an operand or operator.
    ///
    /// - Parameters:
    ///   - node: The leaf or literal.
    ///   - type: Its type.
    ///   - isAtomic: Whether it's a literal counted whole, such as a string.
    ///   - tokens: The operator and operand tokens so far.
    private func record(_ node: Node, type: String, isAtomic: Bool, into tokens: inout HalsteadTokens) {
        if isAtomic || (node.isNamed && type != "comment") {
            tokens.operands.append(text(node) ?? type)
        } else if !Self.closingTokens.contains(type) {
            tokens.operators.append(type)
        }
    }

    /// Operator and operand token texts, gathered during a Halstead walk.
    typealias HalsteadTokens = (operators: [String], operands: [String])
}
