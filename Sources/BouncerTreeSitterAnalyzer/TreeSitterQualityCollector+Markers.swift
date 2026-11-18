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
        if type == quality.ternaryNodeType, hasTernaryAncestor(node) { found.append(.nestedTernary) }
        if type == quality.catchNodeType, isEmptyBlock(node.child(byFieldName: "body")) { found.append(.emptyCatch) }
        if type == quality.numberNodeType, isMagicNumber(node) { found.append(.magicNumber) }
        return found
    }

    /// Finds the first statement in a block that follows an unconditional jump.
    ///
    /// - Parameters:
    ///   - node: A block-like node.
    ///   - type: Its type.
    /// - Returns: The unreachable statement, or `nil` if the block has none.
    func unreachableStatement(in node: Node, type: String) -> Node? {
        guard quality.blockNodeTypes.contains(type) else { return nil }
        let children = (0..<node.namedChildCount).compactMap { node.namedChild(at: $0) }
        guard let jump = children.firstIndex(where: { quality.jumpNodeTypes.contains($0.nodeType ?? "") }) else {
            return nil
        }
        return children[(jump + 1)...].first { !quality.hoistedNodeTypes.contains($0.nodeType ?? "") }
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
            if type == quality.ternaryNodeType { return true }
            current = parent.parent
        }
        return false
    }

    /// Reports whether a block has no statements and no explanatory comment.
    ///
    /// - Parameter block: The block, if present.
    /// - Returns: Whether it's present and empty.
    private func isEmptyBlock(_ block: Node?) -> Bool {
        block?.namedChildCount == 0
    }

    /// Reports whether a number literal is neither trivially small nor named by what holds it.
    ///
    /// - Parameter node: The number literal.
    /// - Returns: Whether it's a magic number.
    private func isMagicNumber(_ node: Node) -> Bool {
        guard let value = text(node), !quality.allowedNumbers.contains(value) else { return false }
        var current = node.parent
        while let parent = current, let type = parent.nodeType {
            if quality.numberNamingParents.contains(type) { return false }
            guard quality.numberTransparentParents.contains(type) else { return true }
            current = parent.parent
        }
        return true
    }
}
