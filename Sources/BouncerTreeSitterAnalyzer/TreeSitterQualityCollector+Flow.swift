import SwiftTreeSitter
import BouncerRules

/// `if` pyramids, loop jumps, and unconditional recursion, from one walk of a function body.
///
/// Jumps go to their target as the language resolves them: an unlabeled `break` to the innermost loop or
/// `switch`, an unlabeled `continue` to the innermost loop, and a labeled one to the statement with that
/// label; only jumps out of loops count. A self-call is a bare call by the function's name, or for a
/// method a call through `this`/`self`, outside nested functions; it has no base case when the body has
/// no branch, loop, throw, short circuit, or optional chain outside them either.
extension TreeSitterQualityCollector {
    /// A statement a jump can target; `isLoop` is false for a `switch`.
    private struct JumpTarget {
        let label: String?
        let isLoop: Bool
        var jumps = 0
    }

    /// Running totals for one body's flow walk.
    private struct FlowTally {
        /// Jump targets, innermost last; `nil` marks a nested function, which jumps can't leave.
        var targets: [JumpTarget?] = []
        var maxLoopJumps = 0
        var arrowDepth = 0
        var conditionals = 0
        var selfCalls = 0

        /// Whether the walk is outside every nested function.
        var isAtTopLevel: Bool { !targets.contains { $0 == nil } }
    }

    /// Measures a function body's flow.
    ///
    /// - Parameters:
    ///   - node: The function node, to tell a method from a plain function.
    ///   - body: Its body.
    ///   - name: Its resolved name, for recognizing self-calls.
    /// - Returns: Its flow measurements.
    func flowMetrics(of node: Node, body: Node, name: String) -> FlowMetrics {
        guard let flow = quality.flow else { return FlowMetrics() }
        var tally = FlowTally()
        tally.arrowDepth = arrowDepth(of: body, flow: flow)
        let call = selfCall(of: node, name: name, flow: flow)
        walkChildren(of: body, flow: flow, selfCall: call, tally: &tally)
        return FlowMetrics(
            npath: paths(through: body, flow: flow), arrowDepth: tally.arrowDepth, maxLoopJumps: tally.maxLoopJumps,
            recursesWithoutBaseCase: tally.selfCalls > 0 && tally.conditionals == 0
        )
    }

    /// Describes how the function would call itself: by bare name, or through a receiver for a method.
    ///
    /// - Parameters:
    ///   - node: The function node.
    ///   - name: Its resolved name.
    ///   - flow: The language's flow node types.
    /// - Returns: The receiver (`nil` for a bare call) and name, or `nil` to skip the recursion check.
    private func selfCall(of node: Node, name: String, flow: FlowSpec) -> (receiver: String?, name: String)? {
        guard name != CollectedFunction.anonymousName, !quality.initializerNames.contains(name) else { return nil }
        guard isMethod(node) || node.nodeType == "method_declaration" else { return (nil, name) }
        return flow.selfReceiver.map { ($0, name) }
    }

    /// Reports whether a function is declared in a class body or an `impl` block, within a few levels of wrapping.
    ///
    /// - Parameter node: The function node.
    /// - Returns: Whether a class or type extension encloses it directly.
    func isMethod(_ node: Node) -> Bool {
        [node.parent, node.parent?.parent, node.parent?.parent?.parent].contains {
            let type = $0?.nodeType ?? ""
            return spec.classNodeTypes.contains(type) || spec.typeExtensionNodeTypes[type] != nil
        }
    }

    /// Walks every child of a node.
    ///
    /// - Parameters:
    ///   - node: The parent.
    ///   - flow: The language's flow node types.
    ///   - selfCall: How the function calls itself, if checked.
    ///   - tally: The running totals.
    private func walkChildren(
        of node: Node, flow: FlowSpec, selfCall: (receiver: String?, name: String)?, tally: inout FlowTally
    ) {
        for index in 0..<node.childCount {
            guard let child = node.child(at: index) else { continue }
            walkFlow(child, flow: flow, selfCall: selfCall, tally: &tally)
        }
    }

    /// Scores one node for jumps, branches, and self-calls, then walks its children.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - flow: The language's flow node types.
    ///   - selfCall: How the function calls itself, if checked.
    ///   - tally: The running totals.
    private func walkFlow(
        _ node: Node, flow: FlowSpec, selfCall: (receiver: String?, name: String)?, tally: inout FlowTally
    ) {
        let type = node.nodeType ?? ""
        let opened = openTarget(node, type: type, flow: flow, tally: &tally)
        if tally.isAtTopLevel { scoreTopLevel(node, type: type, flow: flow, selfCall: selfCall, tally: &tally) }
        countJump(node, type: type, flow: flow, tally: &tally)
        walkChildren(of: node, flow: flow, selfCall: selfCall, tally: &tally)
        guard opened, let closed = tally.targets.popLast() else { return }
        if let closed, closed.isLoop { tally.maxLoopJumps = max(tally.maxLoopJumps, closed.jumps) }
    }

    /// Pushes a jump target for a loop or `switch`, or a barrier for a nested function.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - type: Its type.
    ///   - flow: The language's flow node types.
    ///   - tally: The running totals.
    /// - Returns: Whether something was pushed, to pop after the node's children.
    private func openTarget(_ node: Node, type: String, flow: FlowSpec, tally: inout FlowTally) -> Bool {
        if spec.functionNodeTypes.contains(type) || quality.complexity.closureNodeTypes.contains(type) {
            tally.targets.append(nil)
            return true
        }
        let isLoop = flow.loopNodeTypes.contains(type)
        guard isLoop || flow.breakTargetNodeTypes.contains(type) else { return false }
        if isLoop, tally.isAtTopLevel { tally.arrowDepth = max(tally.arrowDepth, loopArrowDepth(node, flow: flow)) }
        tally.targets.append(JumpTarget(label: targetLabel(node, flow: flow), isLoop: isLoop))
        return true
    }

    /// Measures the `if` pyramid ending a loop's body, which `continue` guards could flatten.
    ///
    /// - Parameters:
    ///   - loop: The loop.
    ///   - flow: The language's flow node types.
    /// - Returns: The pyramid's depth.
    private func loopArrowDepth(_ loop: Node, flow: FlowSpec) -> Int {
        loop.child(byFieldName: "body").map { arrowDepth(of: $0, flow: flow) } ?? 0
    }

    /// Counts a branch or self-call outside nested functions.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - type: Its type.
    ///   - flow: The language's flow node types.
    ///   - selfCall: How the function calls itself, if checked.
    ///   - tally: The running totals.
    private func scoreTopLevel(
        _ node: Node, type: String, flow: FlowSpec, selfCall: (receiver: String?, name: String)?,
        tally: inout FlowTally
    ) {
        if flow.baseCaseNodeTypes.contains(type) || logicalOperator(in: node, type: type) { tally.conditionals += 1 }
        guard let selfCall, let chain = quality.conventions.chain, type == chain.callNodeType,
              let callee = node.child(byFieldName: chain.calleeField) else { return }
        let isSelfCall = isSelfReference(callee, receiver: selfCall.receiver, name: selfCall.name, chain: chain)
        if isSelfCall { tally.selfCalls += 1 }
    }

    /// Reports whether a node is a short-circuiting logical operator.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - type: Its type.
    /// - Returns: Whether it's `&&`, `||`, `??`, `and`, or `or`.
    func logicalOperator(in node: Node, type: String) -> Bool {
        guard type == quality.complexity.logicalNodeType else { return false }
        let op = node.child(byFieldName: "operator").flatMap(text)
        return op.map(quality.complexity.logicalOperators.contains) ?? false
    }

    /// Reports whether a callee names the function itself.
    ///
    /// - Parameters:
    ///   - callee: The call's callee.
    ///   - receiver: The receiver a method calls itself through, or `nil` for a bare call.
    ///   - name: The function's name.
    ///   - chain: The language's call and member-access node types.
    /// - Returns: Whether it's `name` or `receiver.name`.
    private func isSelfReference(_ callee: Node, receiver: String?, name: String, chain: ChainSpec) -> Bool {
        guard let receiver else { return callee.nodeType == "identifier" && text(callee) == name }
        guard callee.nodeType == chain.memberNodeType else { return false }
        return callee.child(byFieldName: chain.objectField).flatMap(text) == receiver
            && callee.child(byFieldName: chain.propertyField).flatMap(text) == name
    }

    /// Credits a `break` or `continue` to its target, if that target is a loop.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - type: Its type.
    ///   - flow: The language's flow node types.
    ///   - tally: The running totals.
    private func countJump(_ node: Node, type: String, flow: FlowSpec, tally: inout FlowTally) {
        let isBreak = flow.jumps.breakNodeTypes.contains(type)
        guard isBreak || flow.jumps.continueNodeTypes.contains(type) else { return }
        let label = namedChildren(of: node).first { flow.labelNodeTypes.contains($0.nodeType ?? "") }.flatMap(text)
        for index in tally.targets.indices.reversed() {
            guard let target = tally.targets[index] else { return }
            guard label.map({ target.label == $0 }) ?? (target.isLoop || isBreak) else { continue }
            if target.isLoop { tally.targets[index]?.jumps += 1 }
            return
        }
    }

    /// Reads the label on a loop or `switch`, from its own label child or the labeled statement wrapping it.
    ///
    /// - Parameters:
    ///   - node: The loop or `switch`.
    ///   - flow: The language's flow node types.
    /// - Returns: The label, or `nil`.
    private func targetLabel(_ node: Node, flow: FlowSpec) -> String? {
        if let own = flow.jumps.loopLabelNodeType {
            return namedChildren(of: node).first { $0.nodeType == own }.flatMap(text)
        }
        guard let parent = node.parent, parent.nodeType == flow.labeledNodeType else { return nil }
        return parent.child(byFieldName: "label").flatMap(text)
    }

    /// Measures the `if` pyramid ending a block: an `if` without `else` as its last statement counts one,
    /// plus the pyramid ending that `if`'s own body.
    ///
    /// - Parameters:
    ///   - block: A function or loop body.
    ///   - flow: The language's flow node types.
    /// - Returns: The pyramid's depth.
    func arrowDepth(of block: Node, flow: FlowSpec) -> Int {
        guard let last = finalStatement(in: block), last.nodeType == flow.ifNodeType,
              last.child(byFieldName: "alternative") == nil,
              let consequence = last.child(byFieldName: flow.consequenceField) else { return 0 }
        return 1 + arrowDepth(of: consequence, flow: flow)
    }

    /// Finds a block's last statement, descending into nested statement lists (Go's `block`).
    ///
    /// - Parameter block: The block.
    /// - Returns: Its last non-comment statement.
    private func finalStatement(in block: Node) -> Node? {
        guard let last = namedChildren(of: block).last(where: { $0.nodeType != "comment" }) else { return nil }
        return quality.statements.blockNodeTypes.contains(last.nodeType ?? "") ? finalStatement(in: last) : last
    }

    /// Lists a node's named children.
    ///
    /// - Parameter node: The node.
    /// - Returns: Its named children, in order.
    func namedChildren(of node: Node) -> [Node] {
        (0..<node.namedChildCount).compactMap { node.namedChild(at: $0) }
    }
}
