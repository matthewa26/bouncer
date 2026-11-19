import Foundation
import SwiftTreeSitter
import BouncerRules

/// Walks one method's body for its `MethodDesign`: its own members and fields (through `this`/`self`),
/// other objects' data, its calls, and its `return`s.
final class TreeSitterMethodDesign {
    private let collector: TreeSitterQualityCollector
    private let design: DesignSpec
    private let cohesion: CohesionSpec
    private let chain: ChainSpec
    private let fields: Set<String>
    private let body: Node
    /// Every function node type, named or anonymous, whose `return`s aren't the method's.
    private let functionNodeTypes: Set<String>
    private(set) var ownMembers: Set<String> = []
    private(set) var foreignData: [String: Set<String>] = [:]
    private(set) var fieldAccesses: [FieldAccess] = []
    private(set) var calls: Set<String> = []
    private(set) var conditionFields: Set<String> = []
    private(set) var returnedValues: [String] = []

    /// Walks a method body.
    ///
    /// - Parameters:
    ///   - body: The method's body.
    ///   - fields: The class's field names.
    ///   - collector: The language's quality collector, for its specs and node text.
    init?(body: Node, fields: Set<String>, collector: TreeSitterQualityCollector) {
        guard let design = collector.quality.design, let cohesion = collector.quality.cohesion,
              let chain = collector.quality.conventions.chain else { return nil }
        (self.collector, self.design, self.cohesion, self.chain) = (collector, design, cohesion, chain)
        (self.fields, self.body) = (fields, body)
        functionNodeTypes = collector.spec.functionNodeTypes.union(design.anonymousFunctionNodeTypes)
        walk(body, isNested: false)
    }

    /// Records what one node does, then walks its children.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - isNested: Whether it's inside a function nested in the method, whose `return`s aren't the method's.
    private func walk(_ node: Node, isNested: Bool) {
        let type = node.nodeType ?? ""
        if type == cohesion.memberAccessNodeType { recordMember(node) }
        if type == chain.callNodeType { recordCall(node) }
        if type == returnNodeType, !isNested { returnedValues.append(returnedText(node)) }
        let nested = isNested || functionNodeTypes.contains(type)
        for child in collector.namedChildren(of: node) { walk(child, isNested: nested) }
    }

    /// Reads what a `return` statement returns.
    ///
    /// - Parameter node: The `return` statement.
    /// - Returns: The returned expression's text, or an empty string for a bare `return`.
    private func returnedText(_ node: Node) -> String {
        node.namedChild(at: 0).flatMap(collector.text) ?? ""
    }

    /// The language's `return` statement.
    private var returnNodeType: String { collector.quality.complexity.returnNodeType }

    /// Records a call to a plain lowercase function name; member calls are recorded with their member.
    ///
    /// - Parameter node: The call.
    private func recordCall(_ node: Node) {
        guard let callee = node.child(byFieldName: chain.calleeField), callee.nodeType == "identifier",
              let name = collector.text(callee), name.first?.isLowercase == true else { return }
        calls.insert(name)
        if name == "hasattr", isInCondition(node), let field = checkedAttribute(node) { conditionFields.insert(field) }
    }

    /// Reads the attribute a Python `hasattr(self, "name")` call checks for, as a lazy cache's condition does.
    ///
    /// - Parameter call: The `hasattr` call.
    /// - Returns: The attribute's name, or `nil` if the call doesn't check `self` for a literal name.
    private func checkedAttribute(_ call: Node) -> String? {
        let arguments = call.child(byFieldName: "arguments").map(collector.namedChildren) ?? []
        guard arguments.count == 2, arguments.first.flatMap(collector.text) == cohesion.receiverText else { return nil }
        return arguments.last.flatMap(collector.text)?.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
    }

    /// Records a member access: an own member through `this`/`self`, or another object's data.
    ///
    /// - Parameter node: The member access.
    private func recordMember(_ node: Node) {
        guard let object = node.child(byFieldName: cohesion.objectField),
              let name = node.child(byFieldName: cohesion.propertyField).flatMap(collector.text) else { return }
        if isCallee(node) { calls.insert(name) }
        if collector.text(object) == cohesion.receiverText {
            recordOwn(name, at: node)
        } else if let receiver = collector.otherObjectName(object), !isWriteOrCopy(node),
                  DesignVocabulary.isForeignData(name, isCalled: isCallee(node)) {
            foreignData[receiver, default: []].insert(name)
        }
    }

    /// Records an own member and, for a field, how this access touches it.
    ///
    /// - Parameters:
    ///   - name: The member's name.
    ///   - node: The `this.name` access.
    private func recordOwn(_ name: String, at node: Node) {
        ownMembers.insert(name)
        guard fields.contains(name) else { return }
        let kind = accessKind(of: node)
        let isTopLevel = kind == .assign && node.parent?.parent?.parent?.id == body.id
        fieldAccesses.append(FieldAccess(field: name, kind: kind, isTopLevel: isTopLevel))
        if isInCondition(node) { conditionFields.insert(name) }
    }

    /// Classifies how a `this.field` access touches the field.
    ///
    /// - Parameter node: The access.
    /// - Returns: `.assign` for a plain assignment not reading it, `.mutate` for a compound assignment,
    ///   an assignment to one of its members, or a mutating call on it, and `.read` otherwise.
    private func accessKind(of node: Node) -> FieldAccess.Kind {
        guard let parent = node.parent, let type = parent.nodeType else { return .read }
        if design.assignmentNodeTypes.contains(type), parent.child(byFieldName: "left")?.id == node.id {
            let right = parent.child(byFieldName: "right").flatMap(collector.text) ?? ""
            return right.contains(collector.text(node) ?? "") ? .mutate : .assign
        }
        return design.compoundAssignmentNodeTypes.contains(type) ? .mutate : memberAccessKind(of: parent, object: node)
    }

    /// Classifies a `this.field.member` access as changing the field (assigning the member, or calling a
    /// mutating method like `push`) or reading it.
    ///
    /// - Parameters:
    ///   - parent: The node around the `this.field` access.
    ///   - node: The `this.field` access.
    /// - Returns: `.mutate` or `.read`.
    private func memberAccessKind(of parent: Node, object node: Node) -> FieldAccess.Kind {
        guard parent.nodeType == cohesion.memberAccessNodeType,
              parent.child(byFieldName: cohesion.objectField)?.id == node.id else { return .read }
        let member = parent.child(byFieldName: cohesion.propertyField).flatMap(collector.text) ?? ""
        if isCallee(parent) { return DesignVocabulary.mutatorNames.contains(member) ? .mutate : .read }
        return isAssigned(parent) ? .mutate : .read
    }

    /// Reports whether a node is the left side of any assignment.
    ///
    /// - Parameter node: The node.
    /// - Returns: Whether a plain or compound assignment writes it.
    private func isAssigned(_ node: Node) -> Bool {
        guard let parent = node.parent, let type = parent.nodeType else { return false }
        let isAssignment = design.assignmentNodeTypes.union(design.compoundAssignmentNodeTypes).contains(type)
        let target = parent.child(byFieldName: "left") ?? parent.child(byFieldName: "argument")
        return isAssignment && target?.id == node.id
    }

    /// Reports whether a member access doesn't read another object's data: it's assigned with `=`, or it's
    /// an argument copied as is into a constructor call, as a mapper does.
    ///
    /// - Parameter node: The member access.
    /// - Returns: Whether it's a write or a straight copy.
    private func isWriteOrCopy(_ node: Node) -> Bool {
        guard let parent = node.parent else { return false }
        if design.assignmentNodeTypes.contains(parent.nodeType ?? ""),
           parent.child(byFieldName: "left")?.id == node.id { return true }
        let list = parent.nodeType == "keyword_argument" ? parent.parent : parent
        guard let call = list?.parent, let field = design.constructorFields[call.nodeType ?? ""],
              list?.id == call.child(byFieldName: "arguments")?.id else { return false }
        return call.child(byFieldName: field).flatMap(collector.text)?.first?.isUppercase == true
    }

    /// Reports whether a node is what a call calls.
    ///
    /// - Parameter node: The node.
    /// - Returns: Whether its parent is a call with it as the callee.
    private func isCallee(_ node: Node) -> Bool {
        guard let parent = node.parent, parent.nodeType == chain.callNodeType else { return false }
        return parent.child(byFieldName: chain.calleeField)?.id == node.id
    }

    /// Reports whether a node sits in an `if` statement's condition within the method.
    ///
    /// - Parameter node: The node.
    /// - Returns: Whether some enclosing `if`'s `condition` field contains it.
    private func isInCondition(_ node: Node) -> Bool {
        var child = node
        while let parent = child.parent, parent.id != body.id {
            if parent.nodeType == design.ifNodeType { return parent.child(byFieldName: "condition")?.id == child.id }
            child = parent
        }
        return false
    }
}

extension TreeSitterQualityCollector {
    /// Names another object a member access starts from: a lowercase identifier that isn't `this`, `self`,
    /// `super`, `cls`, or an imported module, or `this.field`.
    ///
    /// - Parameter object: A member access's object.
    /// - Returns: The object's name, or `nil`.
    func otherObjectName(_ object: Node) -> String? {
        if object.nodeType == "identifier", let name = text(object), name.first?.isLowercase == true {
            return ["this", "self", "super", "cls"].contains(name) || moduleNames.contains(name) ? nil : name
        }
        guard let cohesion = quality.cohesion, object.nodeType == cohesion.memberAccessNodeType,
              object.child(byFieldName: cohesion.objectField).flatMap(text) == cohesion.receiverText else { return nil }
        return object.child(byFieldName: cohesion.propertyField).flatMap(text)
    }
}
