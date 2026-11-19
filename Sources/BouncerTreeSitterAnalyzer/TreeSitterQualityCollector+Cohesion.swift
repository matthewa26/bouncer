import SwiftTreeSitter
import BouncerRules

/// A class body's methods, fields, and `this.x` references, from which `structure(of:body:complexity:)`
/// builds LCOM4 and the other cohesion measures.
extension TreeSitterQualityCollector {
    /// Reads one class member as an instance method, if it is one.
    ///
    /// - Parameter member: A class-body member node.
    /// - Returns: The method's name and node: a method, or a field holding a function.
    func method(from member: Node) -> (name: String, node: Node)? {
        guard let type = member.nodeType, !isStatic(member), let cohesion = quality.cohesion else { return nil }
        if cohesion.methodNodeTypes.contains(type) {
            return member.child(byFieldName: "name").flatMap(text).map { ($0, member) }
        }
        guard let nameField = cohesion.fieldNameFields[type], let value = member.child(byFieldName: "value"),
              spec.functionNodeTypes.contains(value.nodeType ?? "") else { return nil }
        return member.child(byFieldName: nameField).flatMap(text).map { ($0, value) }
    }

    /// Counts a class's methods (excluding initializers) and fields, where the language declares fields.
    ///
    /// - Parameter body: The class body node.
    /// - Returns: The class's shape, or `nil` without a cohesion spec that names field declarations.
    func shape(of body: Node) -> TypeShape? {
        guard let cohesion = quality.cohesion, !cohesion.fieldNameFields.isEmpty else { return nil }
        let members = (0..<body.namedChildCount).compactMap { body.namedChild(at: $0) }
        let methods = members.compactMap(method(from:)).filter { !quality.initializerNames.contains($0.name) }
        let fields = members.filter { member in
            cohesion.fieldNameFields[member.nodeType ?? ""] != nil && !holdsFunction(member)
        }
        return TypeShape(methodCount: methods.count, fieldCount: fields.count, isClass: true)
    }

    /// Reports whether a field's value is a function, which makes it a method for these counts.
    ///
    /// - Parameter field: The field declaration.
    /// - Returns: Whether its value is a function expression.
    private func holdsFunction(_ field: Node) -> Bool {
        spec.functionNodeTypes.contains(field.child(byFieldName: "value")?.nodeType ?? "")
    }

    /// Collects every member name a method reaches through `this`, such as `count` in `this.count`.
    ///
    /// - Parameter node: The method node.
    /// - Returns: The referenced member names.
    func thisReferences(in node: Node) -> Set<String> {
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
    func thisMember(of node: Node) -> String? {
        guard let cohesion = quality.cohesion, node.nodeType == cohesion.memberAccessNodeType,
              node.child(byFieldName: cohesion.objectField).flatMap(text) == cohesion.receiverText else { return nil }
        return node.child(byFieldName: cohesion.propertyField).flatMap(text)
    }

    /// Reports whether a class member is declared `static`.
    ///
    /// - Parameter member: The class-body member node.
    /// - Returns: Whether one of its tokens is the `static` keyword.
    func isStatic(_ member: Node) -> Bool {
        guard let keyword = quality.cohesion?.staticKeyword else { return false }
        return (0..<member.childCount).contains { member.child(at: $0)?.nodeType == keyword }
    }
}
