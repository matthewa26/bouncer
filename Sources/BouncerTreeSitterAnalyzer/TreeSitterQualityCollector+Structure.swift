import SwiftTreeSitter
import BouncerRules

/// A class's `TypeStructure`: method field use, complexity, and delegation, from its body's members.
///
/// Fields are declared fields plus every `this.x`/`self.x` a method reaches that isn't a method, since
/// JavaScript and Python classes often create fields by assigning them.
extension TreeSitterQualityCollector {
    /// Measures a class.
    ///
    /// - Parameters:
    ///   - node: The class node, for what its declaration adds (a superclass, decorators, type parameters).
    ///   - body: Its body.
    ///   - complexity: Measures a function body's cyclomatic complexity.
    /// - Returns: Its structure, or `nil` for a language without a cohesion or flow spec.
    func structure(of node: Node, body: Node, complexity: (Node) -> Int) -> TypeStructure? {
        guard quality.cohesion != nil, let flow = quality.flow else { return nil }
        let members = classMembers(of: body), all = members.compactMap(method(from:))
        let methods = all.filter { !quality.initializerNames.contains($0.name) }
        let reached = all.flatMap { thisReferences(in: $0.node) }
        let fields = declaredFields(members).union(reached).subtracting(methods.map(\.name))
        let bodies = members.compactMap(functionDefinition).compactMap(self.body(of:))
        return TypeStructure(methods: methods.map { graphMethod($0, fields: fields) }, fieldNames: fields,
                             methodComplexities: bodies.map(complexity), isPlain: isPlain(node, flow: flow))
    }

    /// Describes one method for the method-field graph.
    ///
    /// - Parameters:
    ///   - method: The method's name and node.
    ///   - fields: The class's field names.
    /// - Returns: Its graph entry.
    private func graphMethod(_ method: (name: String, node: Node), fields: Set<String>) -> CohesionGraph.Method {
        CohesionGraph.Method(
            name: method.name, references: thisReferences(in: method.node),
            delegate: delegate(of: method, fields: fields)
        )
    }

    /// Lists the names of the fields a class body declares, leaving out fields that hold functions.
    ///
    /// - Parameter members: The class body's members.
    /// - Returns: The field names.
    private func declaredFields(_ members: [Node]) -> Set<String> {
        Set(members.compactMap { member -> String? in
            let value = member.child(byFieldName: "value")?.nodeType ?? ""
            guard let field = quality.cohesion?.fieldNameFields[member.nodeType ?? ""],
                  !spec.functionNodeTypes.contains(value) else { return nil }
            return member.child(byFieldName: field).flatMap(text)
        })
    }

    /// Unwraps a class member to the function it defines: a method, a decorated method, or a field holding a function.
    ///
    /// - Parameter member: A class-body member.
    /// - Returns: The function node, or `nil` for any other member.
    func functionDefinition(_ member: Node) -> Node? {
        let type = member.nodeType ?? ""
        if spec.functionNodeTypes.contains(type) { return member }
        if type == "decorated_definition" { return member.child(byFieldName: "definition").flatMap(functionDefinition) }
        let value = member.child(byFieldName: "value")
        return spec.functionNodeTypes.contains(value?.nodeType ?? "") ? value : nil
    }

    /// Reports whether a class isn't exported or abstract and declares no superclass, decorator, or type
    /// parameter.
    ///
    /// - Parameters:
    ///   - node: The class node.
    ///   - flow: The language's flow node types.
    /// - Returns: Whether it's plain.
    private func isPlain(_ node: Node, flow: FlowSpec) -> Bool {
        let wrappers: Set<String> = ["decorated_definition", "export_statement"]
        guard !wrappers.contains(node.parent?.nodeType ?? ""), node.nodeType != "abstract_class_declaration" else {
            return false
        }
        let hasSuperclass = node.child(byFieldName: "superclasses") ?? node.child(byFieldName: "superclass") != nil
        let isDecorated = namedChildren(of: node).contains { flow.classDecorationTypes.contains($0.nodeType ?? "") }
        return !hasSuperclass && !isDecorated
    }

    /// Finds the field a method does nothing but forward to: its only statement calls the same-named
    /// method on a `this.x`/`self.x` field, as in `load() { return this.store.load(); }`.
    ///
    /// - Parameters:
    ///   - method: The method's name and node.
    ///   - fields: The class's field names.
    /// - Returns: The field, or `nil` if the method does anything else.
    private func delegate(of method: (name: String, node: Node), fields: Set<String>) -> String? {
        guard let chain = quality.conventions.chain, let call = onlyCall(in: method.node, chain: chain),
              let callee = call.child(byFieldName: chain.calleeField), callee.nodeType == chain.memberNodeType,
              callee.child(byFieldName: chain.propertyField).flatMap(text) == method.name,
              let receiver = callee.child(byFieldName: chain.objectField), let field = thisMember(of: receiver)
        else { return nil }
        return fields.contains(field) ? field : nil
    }

    /// Finds the call a function body consists of, through `return` and `await`, skipping a docstring.
    ///
    /// - Parameters:
    ///   - function: The function node.
    ///   - chain: The language's call node types.
    /// - Returns: The call, or `nil` if the body holds anything else.
    private func onlyCall(in function: Node, chain: ChainSpec) -> Node? {
        guard let body = function.child(byFieldName: "body") else { return nil }
        let statements = namedChildren(of: body).filter { $0.nodeType != "comment" && !isDocstring($0) }
        guard statements.count == 1, var expression = statements.first?.namedChild(at: 0) else { return nil }
        while expression.nodeType == "await_expression" || expression.nodeType == "await",
              let inner = expression.namedChild(at: 0) {
            expression = inner
        }
        return expression.nodeType == chain.callNodeType ? expression : nil
    }

    /// Reports whether a statement is a docstring: an expression statement holding only a string.
    ///
    /// - Parameter statement: The statement.
    /// - Returns: Whether it's a docstring.
    private func isDocstring(_ statement: Node) -> Bool {
        statement.nodeType == "expression_statement" && statement.namedChild(at: 0)?.nodeType == "string"
    }
}
