import SwiftTreeSitter
import BouncerRules

/// LCOM4 cohesion for classes, from the members in a class body and their `this.x` references.
extension TreeSitterQualityCollector {
    /// Counts how many unrelated groups a class's instance methods split into.
    ///
    /// - Parameter body: The class body node.
    /// - Returns: The LCOM4 group count, per `CohesionGraph`, or `nil` for a language without a cohesion spec.
    func cohesionGroups(of body: Node) -> Int? {
        guard quality.cohesion != nil else { return nil }
        let members = (0..<body.namedChildCount).compactMap { body.namedChild(at: $0) }
        let methods = members.compactMap(method(from:)).filter { !quality.initializerNames.contains($0.name) }
        return CohesionGraph.groupCount(methods.map {
            CohesionGraph.Method(name: $0.name, references: thisReferences(in: $0.node))
        })
    }

    /// Reads one class member as an instance method, if it is one.
    ///
    /// - Parameter member: A class-body member node.
    /// - Returns: The method's name and node: a method, or a field holding a function.
    private func method(from member: Node) -> (name: String, node: Node)? {
        guard let type = member.nodeType, !isStatic(member), let cohesion = quality.cohesion else { return nil }
        if cohesion.methodNodeTypes.contains(type) {
            return member.child(byFieldName: "name").flatMap(text).map { ($0, member) }
        }
        guard let nameField = cohesion.fieldNameFields[type], let value = member.child(byFieldName: "value"),
              spec.functionNodeTypes.contains(value.nodeType ?? "") else { return nil }
        return member.child(byFieldName: nameField).flatMap(text).map { ($0, value) }
    }

    /// Collects every member name a method reaches through `this`, such as `count` in `this.count`.
    ///
    /// - Parameter node: The method node.
    /// - Returns: The referenced member names.
    private func thisReferences(in node: Node) -> Set<String> {
        var names: Set<String> = thisMember(of: node).map { [$0] } ?? []
        for index in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: index) else { continue }
            names.formUnion(thisReferences(in: child))
        }
        return names
    }

    /// Reads the member name from a `this.name` access.
    ///
    /// - Parameter node: Any node.
    /// - Returns: The member name if the node is a `this.name` access, otherwise `nil`.
    private func thisMember(of node: Node) -> String? {
        guard let cohesion = quality.cohesion, node.nodeType == cohesion.memberAccessNodeType,
              node.child(byFieldName: cohesion.objectField).flatMap(text) == cohesion.receiverText else { return nil }
        return node.child(byFieldName: cohesion.propertyField).flatMap(text)
    }

    /// Reports whether a class member is declared `static`.
    ///
    /// - Parameter member: The class-body member node.
    /// - Returns: Whether one of its tokens is the `static` keyword.
    private func isStatic(_ member: Node) -> Bool {
        guard let keyword = quality.cohesion?.staticKeyword else { return false }
        return (0..<member.childCount).contains { member.child(at: $0)?.nodeType == keyword }
    }
}
