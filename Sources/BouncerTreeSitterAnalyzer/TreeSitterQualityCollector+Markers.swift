import SwiftTreeSitter
import BouncerRules

/// Single-location smells, checked node by node during the summary builder's walk.
extension TreeSitterQualityCollector {
    /// Lists every smell one node exhibits.
    ///
    /// - Parameters:
    ///   - node: The node to check.
    ///   - type: Its type.
    /// - Returns: The smells found at this node; usually none.
    func markers(at node: Node, type: String) -> [MarkerKind] {
        var found = quality.markers.filter { matches($0, node: node, type: type) }.map(\.kind)
        if type == quality.complexity.ternaryNodeType, hasTernaryAncestor(node) { found.append(.nestedTernary) }
        if type == quality.statements.catchNodeType, isEmptyBlock(catchBody(of: node)) { found.append(.emptyCatch) }
        if quality.numbers.literalNodeTypes.contains(type), isMagicNumber(node) { found.append(.magicNumber) }
        return found
    }

    /// Finds the first statement in a block that follows an unconditional jump.
    ///
    /// - Parameters:
    ///   - node: A block-like node.
    ///   - type: Its type.
    /// - Returns: The unreachable statement, or `nil` if the block has none.
    func unreachableStatement(in node: Node, type: String) -> Node? {
        let spec = quality.statements
        guard spec.blockNodeTypes.contains(type) else { return nil }
        let children = (0..<node.namedChildCount).compactMap { node.namedChild(at: $0) }
        guard let jump = children.firstIndex(where: { spec.jumpNodeTypes.contains(statementType(of: $0)) }) else {
            return nil
        }
        return children[(jump + 1)...].first { !spec.hoistedNodeTypes.contains($0.nodeType ?? "") }
    }

    /// Reads a statement's type, looking through a wrapper such as Rust's `expression_statement` to its expression.
    ///
    /// - Parameter statement: A block's statement.
    /// - Returns: The type of what it does.
    private func statementType(of statement: Node) -> String {
        let type = statement.nodeType ?? ""
        guard quality.statements.wrapperNodeTypes.contains(type) else { return type }
        return statement.namedChild(at: 0)?.nodeType ?? type
    }

    /// Reports whether a node matches a marker rule's type and, if given, exact text.
    ///
    /// - Parameters:
    ///   - marker: The marker rule.
    ///   - node: The node.
    ///   - type: Its type.
    /// - Returns: Whether the marker applies.
    private func matches(_ marker: NodeMarker, node: Node, type: String) -> Bool {
        guard marker.nodeType == type else { return false }
        return marker.text.map { text(node) == $0 } ?? true
    }

    /// Reports whether a ternary sits inside another ternary within the same function.
    ///
    /// - Parameter node: The ternary.
    /// - Returns: Whether an enclosing ternary exists before a function boundary.
    private func hasTernaryAncestor(_ node: Node) -> Bool {
        var current = node.parent
        while let parent = current, let type = parent.nodeType, !spec.functionNodeTypes.contains(type) {
            if type == quality.complexity.ternaryNodeType { return true }
            current = parent.parent
        }
        return false
    }

    /// Finds a `catch` clause's body: its `body` field, or else its first block child, as in Python.
    ///
    /// - Parameter node: The catch clause.
    /// - Returns: The body block, if found.
    private func catchBody(of node: Node) -> Node? {
        if let body = node.child(byFieldName: "body") { return body }
        let children = (0..<node.namedChildCount).compactMap { node.namedChild(at: $0) }
        return children.first { quality.statements.blockNodeTypes.contains($0.nodeType ?? "") }
    }

    /// Reports whether a block does nothing: no statements beyond no-ops like `pass`, and no comment.
    ///
    /// - Parameter block: The block, if present.
    /// - Returns: Whether it's present and empty.
    private func isEmptyBlock(_ block: Node?) -> Bool {
        guard let block else { return false }
        let children = (0..<block.namedChildCount).compactMap { block.namedChild(at: $0) }
        return children.allSatisfy { quality.statements.noOpNodeTypes.contains($0.nodeType ?? "") }
    }

    /// Reports whether a number literal is neither trivially small nor named by what holds it.
    ///
    /// - Parameter node: The number literal.
    /// - Returns: Whether it's a magic number.
    private func isMagicNumber(_ node: Node) -> Bool {
        guard let value = text(node), !quality.numbers.allowed.contains(value) else { return false }
        return !isNamed(node)
    }

    /// Walks up through arithmetic, grouping, and call arguments to see whether something names a number.
    ///
    /// - Parameter node: The number literal.
    /// - Returns: Whether a naming parent, such as a declaration or keyword argument, encloses it.
    private func isNamed(_ node: Node) -> Bool {
        let spec = quality.numbers
        var current = node.parent
        while let parent = current, let type = parent.nodeType {
            if spec.namingParents.contains(type) { return true }
            guard spec.transparentParents.contains(type) else { return false }
            current = parent.parent
        }
        return false
    }
}
