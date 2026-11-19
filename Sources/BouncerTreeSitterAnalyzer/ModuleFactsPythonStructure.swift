import SwiftTreeSitter
import BouncerCore

/// Collects Python structure facts: classes (protocols and abstract base classes told apart), functions
/// and methods, and `match` subjects.
final class PythonStructure: StructureCollector {
    private static let receivers: Set<String> = ["self", "cls"]
    private static let noOps: Set<String> = ["pass_statement", "ellipsis"]
    private static let parameterTypes: Set<String> = [
        "identifier", "default_parameter", "typed_parameter", "typed_default_parameter"
    ]

    /// Records a declaration by its node type.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - owner: The enclosing class's name, if any.
    /// - Returns: The class's name for a class, else `owner`.
    override func record(_ node: Node, owner: String?) -> String? {
        switch node.nodeType {
        case "class_definition": return recordClass(node) ?? owner
        case "function_definition": recordFunction(node, owner: owner)
        case "match_statement": recordMatch(node)
        default: break
        }
        return owner
    }

    /// Records a class with its bases, annotated fields, and methods.
    ///
    /// - Parameter node: The class definition.
    /// - Returns: The class's name.
    private func recordClass(_ node: Node) -> String? {
        guard let name = field(node, "name") else { return nil }
        let bases = node.child(byFieldName: "superclasses").map(TreeWalk.namedChildren) ?? []
        var members = TypeMembers(supertypes: bases.compactMap(baseName))
        let statements = node.child(byFieldName: "body").map(TreeWalk.namedChildren) ?? []
        let isAbstract = statements.map { addMember($0, to: &members) }.contains(true)
            || bases.contains { text($0)?.contains("ABCMeta") == true }
        add(TypeFact(name: name, line: TreeWalk.line(node), kind: kind(bases: members.supertypes, isAbstract),
                     members: members))
        return name
    }

    /// Decides a class's kind from its bases and methods.
    ///
    /// - Parameters:
    ///   - bases: Its base classes' names.
    ///   - hasAbstractMethods: Whether it uses `ABCMeta` or declares an `@abstractmethod`.
    /// - Returns: `.protocol` for a `typing.Protocol`, `.abstractClass` for an ABC, else `.class`.
    private func kind(bases: [String], _ hasAbstractMethods: Bool) -> TypeKind {
        if bases.contains("Protocol") { return .protocol }
        return hasAbstractMethods || bases.contains("ABC") ? .abstractClass : .class
    }

    /// Reads a base class's name, skipping keyword arguments such as `metaclass=`.
    ///
    /// - Parameter node: An argument in the class's base list.
    /// - Returns: The base's bare name, or `nil`.
    private func baseName(_ node: Node) -> String? {
        ["identifier", "attribute", "subscript"].contains(node.nodeType) ? text(node).map(FactText.typeName) : nil
    }

    /// Adds one class-body statement: an annotated field, or a method.
    ///
    /// - Parameters:
    ///   - statement: The statement.
    ///   - members: The class's members so far.
    /// - Returns: Whether the statement is an `@abstractmethod`.
    private func addMember(_ statement: Node, to members: inout TypeMembers) -> Bool {
        if let field = annotatedField(statement) { members.fields.append(field) }
        let function = statement.nodeType == "decorated_definition"
            ? statement.child(byFieldName: "definition") : statement
        guard let function, function.nodeType == "function_definition", let name = field(function, "name") else {
            return false
        }
        if name != "__init__" { Self.addMethod(name, body: classify(function), to: &members) }
        return statement.nodeType == "decorated_definition" && text(statement)?.contains("abstractmethod") == true
    }

    /// Reads a class-level `name: Type` field, as dataclasses and typed classes declare them.
    ///
    /// - Parameter statement: A class-body statement.
    /// - Returns: `name:Type`, or `nil` if it isn't an annotated assignment.
    private func annotatedField(_ statement: Node) -> String? {
        guard statement.nodeType == "expression_statement",
              let assignment = TreeWalk.namedChildren(statement).first, assignment.nodeType == "assignment",
              let type = field(assignment, "type"), let left = assignment.child(byFieldName: "left"),
              left.nodeType == "identifier", let name = text(left) else { return nil }
        return FactText.member(name, type: type)
    }

    /// Classifies a method's body, ignoring its docstring and comments.
    ///
    /// - Parameter function: The function definition.
    /// - Returns: `.empty` for only `pass` or `...`, `.refused` for only a `raise`, else `nil`.
    private func classify(_ function: Node) -> MethodBody? {
        let statements = (function.child(byFieldName: "body").map(TreeWalk.namedChildren) ?? []).filter { node in
            node.nodeType != "comment" && !isDocstring(node)
        }
        let unwrapped = statements.map { node in
            node.nodeType == "expression_statement" ? TreeWalk.namedChildren(node).first ?? node : node
        }
        return Self.classify(unwrapped, throwType: "raise_statement", noOps: Self.noOps)
    }

    /// Reports whether a statement is a bare string, as a docstring is.
    ///
    /// - Parameter node: A statement.
    /// - Returns: Whether it's a string expression statement.
    private func isDocstring(_ node: Node) -> Bool {
        node.nodeType == "expression_statement" && TreeWalk.namedChildren(node).first?.nodeType == "string"
    }

    /// Records a function, naming `__init__` `<Class>.init` and leaving out `self` and `cls`.
    ///
    /// - Parameters:
    ///   - node: The function definition.
    ///   - owner: The enclosing class's name, if any.
    private func recordFunction(_ node: Node, owner: String?) {
        let name = field(node, "name")
        let list = node.child(byFieldName: "parameters").map(TreeWalk.namedChildren) ?? []
        let parameters = list.compactMap(parameter).filter { !Self.receivers.contains($0) }
        addFunction(name == "__init__" ? (owner ?? "") + ".init" : name, node, parameters: parameters)
    }

    /// Reads one parameter as `name:Type` or `name`.
    ///
    /// - Parameter node: A parameter.
    /// - Returns: The parameter, or `nil` for `*args`, `**kwargs`, and separators.
    private func parameter(_ node: Node) -> String? {
        guard Self.parameterTypes.contains(node.nodeType ?? "") else { return nil }
        let named = node.nodeType == "identifier" ? node
            : node.child(byFieldName: "name") ?? TreeWalk.namedChildren(node).first
        guard let named, named.nodeType == "identifier", let name = text(named) else { return nil }
        return FactText.member(name, type: field(node, "type"))
    }

    /// Records a `match` statement's subject, skipping `match a, b:` tuples.
    ///
    /// - Parameter node: The match statement.
    private func recordMatch(_ node: Node) {
        guard node.child(at: 2)?.nodeType != "," else { return }
        addSwitch(node.child(byFieldName: "subject"), node)
    }
}
