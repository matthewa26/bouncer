import SwiftTreeSitter
import BouncerRules

/// `tell-dont-ask`: an `if` whose condition reads a member of another object (a parameter, field, or
/// global, not one of the enclosing function's own locals) and whose body changes that same member, by
/// assigning it or calling its setter, as in `if (account.balance >= x) { account.balance -= x; }`.
extension TreeSitterQualityCollector {
    /// Reports whether an `if` asks an object about its state and then tells it what to be.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - type: Its type.
    /// - Returns: Whether it's an ask-then-tell `if`.
    func isTellDontAsk(_ node: Node, type: String) -> Bool {
        guard let design = quality.design, let chain = quality.conventions.chain, type == design.ifNodeType,
              let condition = node.child(byFieldName: "condition"),
              let consequence = node.child(byFieldName: "consequence") else { return false }
        let asked = Set(([condition] + descendants(of: condition)).compactMap { askedState($0, chain: chain) })
        let told = asked.isEmpty ? [] : Set(descendants(of: consequence).flatMap {
            toldStates($0, design: design, chain: chain)
        }).intersection(asked)
        let locals = told.isEmpty ? [] : localNames(around: node, design: design)
        return told.contains { !locals.contains($0.object) }
    }

    /// Reads which other object's state a member access names.
    ///
    /// - Parameters:
    ///   - member: Any node.
    ///   - chain: The language's call and member-access node types.
    /// - Returns: The object's source text and the state's name, or `nil` if the node isn't a member access or
    ///   the object is `this`/`self`, a type, a module, or an expression.
    private func askedState(_ member: Node, chain: ChainSpec) -> ObjectState? {
        guard member.nodeType == chain.memberNodeType, let object = member.child(byFieldName: chain.objectField),
              otherObjectName(object) != nil,
              let objectText = text(object),
              let name = member.child(byFieldName: chain.propertyField).flatMap(text),
              !DesignVocabulary.isLibraryAccessor(name) else { return nil }
        return ObjectState(object: objectText, state: DesignVocabulary.stateName(of: name))
    }

    /// Lists the other objects' state a node changes: the member an assignment or `++` writes, or the
    /// state whose setter a call calls.
    ///
    /// - Parameters:
    ///   - node: Any node in the `if` body.
    ///   - design: The language's design node types.
    ///   - chain: The language's call and member-access node types.
    /// - Returns: The changed state; usually none.
    private func toldStates(_ node: Node, design: DesignSpec, chain: ChainSpec) -> [ObjectState] {
        if let setter = setterCallee(node, chain: chain) { return askedState(setter, chain: chain).map { [$0] } ?? [] }
        guard design.assignmentNodeTypes.union(design.compoundAssignmentNodeTypes).contains(node.nodeType ?? ""),
              let target = node.child(byFieldName: "left") ?? node.child(byFieldName: "argument")
                ?? node.namedChild(at: 0) else { return [] }
        let targets = target.nodeType == "expression_list" ? namedChildren(of: target) : [target]
        return targets.filter { $0.nodeType == chain.memberNodeType }.compactMap { askedState($0, chain: chain) }
    }

    /// Finds the member a call calls when it's a setter, as in `account.setBalance(0)`.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - chain: The language's call and member-access node types.
    /// - Returns: The called member access, or `nil` if the node isn't a call to a `setX` member.
    private func setterCallee(_ node: Node, chain: ChainSpec) -> Node? {
        guard node.nodeType == chain.callNodeType, let callee = node.child(byFieldName: chain.calleeField),
              callee.nodeType == chain.memberNodeType else { return nil }
        let name = callee.child(byFieldName: chain.propertyField).flatMap(text) ?? ""
        return DesignVocabulary.isSetter(name) ? callee : nil
    }

    /// Lists the locals of the function declaration around a node: its variables, loop and pattern
    /// bindings, closures' parameters, and (Go) its receiver, which is the object itself.
    ///
    /// - Parameters:
    ///   - node: A node inside a function.
    ///   - design: The language's design node types.
    /// - Returns: The local names, or none at file scope.
    private func localNames(around node: Node, design: DesignSpec) -> Set<String> {
        var current = node.parent
        while let function = current {
            let type = function.nodeType ?? ""
            if spec.functionNodeTypes.contains(type), !design.anonymousFunctionNodeTypes.contains(type) {
                return Set(bindingNodes(in: function, design: design).flatMap(boundIdentifiers))
            }
            current = function.parent
        }
        return []
    }

    /// Lists the nodes that bind a function's locals.
    ///
    /// - Parameters:
    ///   - function: The function declaration.
    ///   - design: The language's design node types.
    /// - Returns: Each local binding's name or pattern, each closure parameter, and any Go receiver.
    private func bindingNodes(in function: Node, design: DesignSpec) -> [Node] {
        let inside = descendants(of: function)
        let bindings = inside.compactMap { node in
            design.localBindings[node.nodeType ?? ""].flatMap { node.child(byFieldName: $0) }
        }
        let closures = inside.filter { design.anonymousFunctionNodeTypes.contains($0.nodeType ?? "") }
        return bindings + closures.flatMap(parameterNodes) + [function.child(byFieldName: "receiver")].compactMap { $0 }
    }

    /// Lists the names a binding or pattern binds, leaving out the parts of member accesses and subscripts.
    ///
    /// - Parameter node: A binding's name, pattern, or parameter.
    /// - Returns: The identifiers it binds.
    private func boundIdentifiers(_ node: Node) -> [String] {
        let member = quality.conventions.chain?.memberNodeType
        let names = ([node] + descendants(of: node)).filter { candidate in
            let kind = candidate.nodeType ?? "", parent = candidate.parent?.nodeType
            let isName = kind == "identifier" || kind == "shorthand_property_identifier_pattern"
            return isName && (candidate.id == node.id || (parent != member && parent != "subscript"))
        }
        return node.nodeType == member ? [] : names.compactMap(text)
    }
}
