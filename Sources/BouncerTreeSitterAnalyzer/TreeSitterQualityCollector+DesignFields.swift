import SwiftTreeSitter
import BouncerRules

/// A class's field declarations and the other types it names, for `TypeDesign`.
extension TreeSitterQualityCollector {
    /// Lists a class's fields: those its body declares, then those only created by assigning
    /// `this.x`/`self.x`, at their first assignment. A field created that way is only private by its
    /// `_` name, so it can't be temporary in a class with a superclass, or when code elsewhere in the file
    /// (a subclass, say) reaches `this.x`/`self.x` too.
    ///
    /// - Parameters:
    ///   - node: The class node.
    ///   - body: Its body.
    ///   - assigned: Every assigned `this.x`/`self.x`, with its line, in source order.
    ///   - methodNames: The class's method names, which aren't fields.
    ///   - line: Finds a node's 1-indexed line.
    /// - Returns: The fields, each marked whether it could be temporary.
    func fieldDeclarations(
        of node: Node, body: Node, assigned: [(name: String, line: Int)], methodNames: Set<String>,
        line: (Node) -> Int
    ) -> [FieldDeclaration] {
        let declared = namedChildren(of: body).compactMap { declaredField($0, line: line) }
        var seen = Set(declared.map(\.name)).union(methodNames)
        let created = assigned.filter { seen.insert($0.name).inserted }
        let shared = created.contains { Self.isPrivateName($0.name) } ? fieldsShared(beyond: node) : nil
        return declared + created.map { field in
            let isCandidate = Self.isPrivateName(field.name) && shared?.contains(field.name) == false
            return FieldDeclaration(name: field.name, line: field.line, isTemporaryCandidate: isCandidate)
        }
    }

    /// Lists the `this.x`/`self.x` members a class shares with other code: every one if it has a superclass,
    /// and otherwise those reached anywhere in the file outside it.
    ///
    /// - Parameter node: The class node.
    /// - Returns: The shared member names, or `nil` when every member may be shared.
    private func fieldsShared(beyond node: Node) -> Set<String>? {
        guard !inherits(node) else { return nil }
        var root = node
        while let parent = root.parent { root = parent }
        let outside = descendants(of: root).filter {
            $0.byteRange.lowerBound < node.byteRange.lowerBound || $0.byteRange.upperBound > node.byteRange.upperBound
        }
        return Set(outside.compactMap(thisMember(of:)))
    }

    /// Reports whether a class declares a superclass: a Python base other than `object`, or a TS/JS `extends`.
    ///
    /// - Parameter node: The class node.
    /// - Returns: Whether it inherits.
    private func inherits(_ node: Node) -> Bool {
        let superclasses = node.child(byFieldName: "superclasses").map(namedChildren)?.compactMap(text) ?? []
        return superclasses.contains { $0 != "object" }
            || namedChildren(of: node).contains { $0.nodeType == "class_heritage" }
    }

    /// Reads one class-body member as a field declaration, if it declares one that doesn't hold a function.
    ///
    /// - Parameters:
    ///   - member: A class-body member.
    ///   - line: Finds a node's 1-indexed line.
    /// - Returns: The field, or `nil` for any other member.
    private func declaredField(_ member: Node, line: (Node) -> Int) -> FieldDeclaration? {
        guard let nameField = quality.cohesion?.fieldNameFields[member.nodeType ?? ""],
              functionDefinition(member) == nil,
              let name = member.child(byFieldName: nameField).flatMap(text) else { return nil }
        return FieldDeclaration(
            name: name, line: line(member), typeName: annotation(of: member),
            isTemporaryCandidate: isTemporaryCandidate(member, name)
        )
    }

    /// Reads a declaration's type annotation, without TypeScript's leading `:`.
    ///
    /// - Parameter node: A field or parameter.
    /// - Returns: Its `type` field's text, if it has one.
    private func annotation(of node: Node) -> String? {
        node.child(byFieldName: "type").flatMap(text).map { String($0.drop { $0 == ":" || $0 == " " }) }
    }

    /// Reports whether a declared field could be temporary: private (by `private`, `#`, or `_`), not static,
    /// read-only, or decorated, and declared without a value other than `null`/`undefined`.
    ///
    /// - Parameters:
    ///   - member: The field declaration.
    ///   - name: The field's name.
    /// - Returns: Whether it's a candidate.
    private func isTemporaryCandidate(_ member: Node, _ name: String) -> Bool {
        let tokens = (0..<member.childCount).compactMap { member.child(at: $0) }
        let modifiers = tokens.compactMap(text)
        let isPrivate = Self.isPrivateName(name) || modifiers.contains(quality.design?.privateModifierText ?? "#")
        let value = member.child(byFieldName: "value").flatMap(text)
        let isMarked = tokens.contains { $0.nodeType == "decorator" || $0.nodeType == quality.design?.readonlyKeyword }
        return isPrivate && !isMarked && !isStatic(member) && (value == nil || value == "null" || value == "undefined")
    }

    /// Reports whether a name marks a field private by convention: `#x`, `_x`, or Python's `__x`, but not a
    /// dunder like `__x__`.
    ///
    /// - Parameter name: The field's name.
    /// - Returns: Whether it's private.
    static func isPrivateName(_ name: String) -> Bool {
        name.hasPrefix("#") || (name.hasPrefix("_") && !(name.hasPrefix("__") && name.hasSuffix("__")))
    }

    /// Lists the parameters a caller must pass, with their declared types, for `primitive-obsession`;
    /// defaulted, optional, and variadic parameters are left out.
    ///
    /// - Parameters:
    ///   - node: The function node.
    ///   - line: The line to record them on.
    /// - Returns: One name per required parameter, with its type annotation if it has one.
    func typedParameters(of node: Node, line: Int) -> [CollectedName] {
        let optional = quality.design?.optionalParameterNodeTypes ?? []
        let required = parameterNodes(of: node).filter {
            !optional.contains($0.nodeType ?? "") && $0.child(byFieldName: "value") == nil
        }
        return required.flatMap { parameter in
            parameterNames(parameter).map {
                CollectedName(name: $0, line: line, typeName: annotation(of: parameter), isParameter: true)
            }
        }
    }

    /// Reads the names one parameter entry declares: itself if it's a bare identifier, its `name` or
    /// `pattern` fields (Go groups several names), or else its first child (Python's typed parameter).
    ///
    /// - Parameter parameter: A parameter entry.
    /// - Returns: Its plain identifier names; destructuring patterns give none.
    private func parameterNames(_ parameter: Node) -> [String] {
        let fields = (0..<parameter.childCount).filter {
            ["name", "pattern"].contains(parameter.fieldNameForChild(at: $0) ?? "")
        }.compactMap { parameter.child(at: $0) }
        let named = fields.isEmpty ? Array(namedChildren(of: parameter).prefix(1)) : fields
        return (parameter.nodeType == "identifier" ? [parameter] : named).filter { $0.nodeType == "identifier" }
            .compactMap(text)
    }

    /// Lists the other types a class names, for CBO: type annotations, heritage, constructor calls, and
    /// uppercase objects of member access, minus its own name, nested classes, and generic parameters.
    ///
    /// - Parameters:
    ///   - node: The class node.
    ///   - design: The language's design node types.
    /// - Returns: The type names.
    func typeReferences(of node: Node, design: DesignSpec) -> Set<String> {
        let nodes = ownDescendants(of: node)
        let declared = nodes.filter {
            spec.classNodeTypes.contains($0.nodeType ?? "") || $0.nodeType == design.genericParameterNodeType
        }
        let excluded = Set(([node] + declared).compactMap { $0.child(byFieldName: "name").flatMap(text) })
        let superclasses = design.superclassField.flatMap { node.child(byFieldName: $0) }.map(identifiers) ?? []
        let named = nodes.flatMap { typeNames(at: $0, design: design) } + superclasses
        return Set(named).subtracting(excluded).filter(Self.isTypeLikeName)
    }

    /// Lists a class's descendants, stopping at nested classes (which are listed, but not entered).
    ///
    /// - Parameter node: The class node, or a node inside it.
    /// - Returns: The descendants.
    private func ownDescendants(of node: Node) -> [Node] {
        namedChildren(of: node).flatMap { child in
            spec.classNodeTypes.contains(child.nodeType ?? "") ? [child] : [child] + ownDescendants(of: child)
        }
    }

    /// Reads the type names one node mentions directly.
    ///
    /// - Parameters:
    ///   - node: A node inside the class.
    ///   - design: The language's design node types.
    /// - Returns: A type name's text, an annotation's or heritage clause's identifiers, a constructor call's
    ///   identifier callee, or a member access's identifier object; usually nothing.
    private func typeNames(at node: Node, design: DesignSpec) -> [String] {
        let type = node.nodeType ?? ""
        if design.typeNameNodeTypes.contains(type) { return text(node).map { [$0] } ?? [] }
        if design.typeContainerNodeTypes.contains(type) { return identifiers(in: node) }
        let callee = design.constructorFields[type].flatMap { node.child(byFieldName: $0) }
        let chain = quality.conventions.chain
        let object = type == chain?.memberNodeType ? chain.flatMap { node.child(byFieldName: $0.objectField) } : nil
        return [callee, object].compactMap { $0 }.filter { $0.nodeType == "identifier" }.compactMap(text)
    }

    /// Lists the identifiers anywhere inside a node.
    ///
    /// - Parameter node: The node.
    /// - Returns: The text of each `identifier` or `type_identifier` in it.
    private func identifiers(in node: Node) -> [String] {
        ([node] + descendants(of: node)).filter { ["identifier", "type_identifier"].contains($0.nodeType ?? "") }
            .compactMap(text)
    }

    /// Reports whether a name looks like a type: it starts uppercase and isn't a `SCREAMING_CASE` constant.
    ///
    /// - Parameter name: The name.
    /// - Returns: Whether it could name a type.
    private static func isTypeLikeName(_ name: String) -> Bool {
        guard name.first?.isUppercase == true else { return false }
        return !(name.contains("_") && name == name.uppercased())
    }
}
