import SwiftTreeSitter
import BouncerRules

/// Each outermost member chain's reach past its first object, for `law-of-demeter`.
extension TreeSitterQualityCollector {
    /// Measures the chain a node ends, if it's the outermost member access or call of one.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - type: Its type.
    /// - Returns: The chain's reach, or `nil` if the node doesn't end a measured chain.
    func demeterReach(_ node: Node, type: String) -> Int? {
        guard let chain = quality.conventions.chain, type == chain.memberNodeType || type == chain.callNodeType,
              isChainTop(node, chain: chain) else { return nil }
        let (base, segments) = decompose(node, chain: chain)
        guard !moduleNames.contains(base ?? "") else { return nil }
        let reach = DemeterChain.reach(base: base, segments: segments, uppercaseIsType: chain.uppercaseIsType)
        return reach > 0 ? reach : nil
    }

    /// Reports whether no member access or call continues a node's chain.
    ///
    /// - Parameters:
    ///   - node: A member access or call.
    ///   - chain: The language's call and member-access node types.
    /// - Returns: Whether it's the chain's outermost node.
    private func isChainTop(_ node: Node, chain: ChainSpec) -> Bool {
        guard let parent = node.parent else { return true }
        let field = parent.nodeType == chain.callNodeType ? chain.calleeField
            : parent.nodeType == chain.memberNodeType ? chain.objectField : nil
        if let field { return parent.child(byFieldName: field)?.id != node.id }
        return parent.nodeType != "non_null_expression"
    }

    /// Splits a chain into the name it starts from and its member accesses.
    ///
    /// - Parameters:
    ///   - node: The chain's outermost node, or a part of it.
    ///   - chain: The language's call and member-access node types.
    ///   - isCalled: Whether the caller calls this part.
    /// - Returns: The base name (`nil` for a literal or other expression) and the segments, in order.
    private func decompose(
        _ node: Node, chain: ChainSpec, isCalled: Bool = false
    ) -> (String?, [DemeterChain.Segment]) {
        if let (inner, calls) = passThrough(node, chain: chain) {
            return decompose(inner, chain: chain, isCalled: isCalled || calls)
        }
        let type = node.nodeType ?? ""
        guard type == chain.memberNodeType else { return (Self.baseNodeTypes.contains(type) ? text(node) : nil, []) }
        let name = node.child(byFieldName: chain.propertyField).flatMap(text) ?? ""
        let object = node.child(byFieldName: chain.objectField)
        let (base, segments) = object.map { decompose($0, chain: chain) } ?? (nil, [])
        return (base, segments + [DemeterChain.Segment(name: name, isCall: isCalled)])
    }

    /// Looks through a call to its callee, or through a TypeScript `!` to its operand.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - chain: The language's call and member-access node types.
    /// - Returns: The inner node and whether it's called, or `nil` for any other node.
    private func passThrough(_ node: Node, chain: ChainSpec) -> (Node, Bool)? {
        if node.nodeType == "non_null_expression" { return node.namedChild(at: 0).map { ($0, false) } }
        guard node.nodeType == chain.callNodeType else { return nil }
        return node.child(byFieldName: chain.calleeField).map { ($0, true) }
    }

    private static let baseNodeTypes: Set<String> = ["identifier", "this", "self"]
}
