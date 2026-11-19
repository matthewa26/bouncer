import Foundation
import SwiftTreeSitter
import BouncerRules

/// A class's `TypeDesign`: the other types it names, its fields, and what each method does with its own
/// members and with other objects.
///
/// Fields are declared fields plus every `this.x`/`self.x` some method assigns, since JavaScript and
/// Python classes often create fields by assigning them.
extension TreeSitterQualityCollector {
    /// Measures a class.
    ///
    /// - Parameters:
    ///   - node: The class node, for its name, heritage, and type references.
    ///   - body: Its body.
    ///   - line: Finds a node's 1-indexed line.
    /// - Returns: Its design facts, or `nil` for a language without a cohesion or design spec.
    func design(of node: Node, body: Node, line: (Node) -> Int) -> TypeDesign? {
        guard quality.cohesion != nil, let design = quality.design else { return nil }
        let functions = namedChildren(of: body).compactMap { member in functionDefinition(member).map { (member, $0) } }
        let methodNames = Set(functions.compactMap { memberName(of: $0.1) })
        let assigned = functions.flatMap { assignedFields(in: $0.1, line: line) }
        let fields = fieldDeclarations(of: node, body: body, assigned: assigned, methodNames: methodNames, line: line)
        let fieldNames = Set(fields.map(\.name))
        return TypeDesign(referencedTypes: typeReferences(of: node, design: design), methods: functions.compactMap {
            methodDesign(member: $0.0, function: $0.1, fields: fieldNames, line: line)
        }, fields: fields)
    }

    /// Reads a method's name.
    ///
    /// - Parameter function: The method's function node.
    /// - Returns: Its name, from the method itself or the field holding it.
    private func memberName(of function: Node) -> String? {
        if let name = function.child(byFieldName: "name").flatMap(text) { return name }
        let field = function.parent.flatMap { quality.cohesion?.fieldNameFields[$0.nodeType ?? ""] }
        return field.flatMap { function.parent?.child(byFieldName: $0) }.flatMap(text)
    }

    /// Measures one method.
    ///
    /// - Parameters:
    ///   - member: The class-body member: the method, its decorated wrapper, or the field holding it.
    ///   - function: The function node.
    ///   - fields: The class's field names.
    ///   - line: Finds a node's 1-indexed line.
    /// - Returns: Its design facts, or `nil` without a name or body.
    private func methodDesign(member: Node, function: Node, fields: Set<String>, line: (Node) -> Int) -> MethodDesign? {
        guard let name = memberName(of: function), let body = function.child(byFieldName: "body"),
              let walk = TreeSitterMethodDesign(body: body, fields: fields, collector: self) else { return nil }
        let isOverride = namedChildren(of: function).contains { $0.nodeType == quality.design?.overrideNodeType }
        return MethodDesign(
            name: name, line: line(function), kind: methodKind(member, name: name), ownMembers: walk.ownMembers,
            foreignData: walk.foreignData, fieldAccesses: walk.fieldAccesses, calls: walk.calls,
            returnsValue: returnsValue(function, returned: walk.returnedValues),
            conditionFields: walk.conditionFields, isOverride: isOverride
        )
    }

    /// Classifies a method as an initializer, a type-level method (`static`, `@staticmethod`,
    /// `@classmethod`), or an instance method.
    ///
    /// - Parameters:
    ///   - member: The class-body member.
    ///   - name: The method's name.
    /// - Returns: Its kind.
    private func methodKind(_ member: Node, name: String) -> MethodDesign.Kind {
        if quality.initializerNames.contains(name) { return .initializer }
        let decorators = namedChildren(of: member).filter { $0.nodeType == "decorator" }.compactMap(text)
        let typeLevel = quality.design?.typeLevelDecorators ?? []
        let isDecoratedTypeLevel = decorators.contains { typeLevel.contains(String($0.dropFirst())) }
        return isStatic(member) || isDecoratedTypeLevel ? .typeLevel : .instance
    }

    /// Reports whether a method gives its caller a computed value: no `void`-like declared return type, no
    /// `return this`/`return self`, and at least one `return` of something other than a constant (a literal
    /// such as `true` or `None`), which would be a status.
    ///
    /// - Parameters:
    ///   - function: The function node.
    ///   - returned: The text each of its own `return`s returns, empty for a bare `return`.
    /// - Returns: Whether it's a query.
    private func returnsValue(_ function: Node, returned: [String]) -> Bool {
        guard let design = quality.design else { return false }
        let declared = function.child(byFieldName: "return_type").flatMap(text)
            .map { String($0.filter { !$0.isWhitespace }.drop { $0 == ":" }) }
        if let declared, design.voidReturnTypes.contains(declared) { return false }
        guard !returned.contains(where: design.valuelessReturns.contains) else { return false }
        return returned.contains { !$0.isEmpty && !Self.isConstant($0) }
    }

    /// Reports whether returned text is a constant: a keyword literal, a number, or a plain quoted string.
    ///
    /// - Parameter text: The returned expression's text.
    /// - Returns: Whether it's a constant.
    private static func isConstant(_ text: String) -> Bool {
        text.range(of: #"^(true|false|True|False|null|None|undefined|nil|-?[0-9][0-9_.]*|"[^"\\$]*"|'[^'\\]*')$"#,
                   options: .regularExpression) != nil
    }

    /// Lists the `this.x`/`self.x` fields a method assigns, with the line of each assignment.
    ///
    /// - Parameters:
    ///   - function: The method's function node.
    ///   - line: Finds a node's 1-indexed line.
    /// - Returns: Each assigned field's name and line, in source order.
    private func assignedFields(in function: Node, line: (Node) -> Int) -> [(name: String, line: Int)] {
        guard let design = quality.design else { return [] }
        return descendants(of: function).compactMap { node in
            guard design.assignmentNodeTypes.contains(node.nodeType ?? ""),
                  let left = node.child(byFieldName: "left"), let name = thisMember(of: left) else { return nil }
            return (name, line(node))
        }
    }

    /// Lists every descendant of a node, depth first.
    ///
    /// - Parameter node: The node.
    /// - Returns: Its descendants, not including itself.
    func descendants(of node: Node) -> [Node] {
        namedChildren(of: node).flatMap { [$0] + descendants(of: $0) }
    }
}
