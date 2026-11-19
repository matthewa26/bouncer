import SwiftTreeSitter
import BouncerCore

/// Collects TypeScript and JavaScript structure facts: classes, interfaces, and enums; named functions,
/// methods, and arrow functions; and `switch` subjects.
final class JavaScriptStructure: StructureCollector {
    private static let functionValues: Set<String> = ["arrow_function", "function_expression", "function"]
    private static let fieldTypes: Set<String> = ["public_field_definition", "field_definition", "property_signature"]
    private static let parameterTypes: Set<String> = [
        "identifier", "assignment_pattern", "required_parameter", "optional_parameter"
    ]

    /// Records a declaration by its node type.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - owner: The enclosing class's name, if any.
    /// - Returns: The class's name for a class, else `owner`.
    override func record(_ node: Node, owner: String?) -> String? {
        switch node.nodeType {
        case "class_declaration", "abstract_class_declaration": return recordClass(node) ?? owner
        case "interface_declaration", "enum_declaration": recordType(node)
        case "function_declaration", "generator_function_declaration", "method_definition": recordMethod(node, owner)
        case "variable_declarator": recordFunctionValue(node)
        case "switch_statement": addSwitch(node.child(byFieldName: "value"), node)
        default: break
        }
        return owner
    }

    /// Records a class with its supertypes, fields, and methods.
    ///
    /// - Parameter node: The class declaration.
    /// - Returns: The class's name.
    private func recordClass(_ node: Node) -> String? {
        guard let name = field(node, "name") else { return nil }
        let kind: TypeKind = node.nodeType == "abstract_class_declaration" ? .abstractClass : .class
        var members = TypeMembers(supertypes: heritage(of: node))
        for member in node.child(byFieldName: "body").map(TreeWalk.namedChildren) ?? [] {
            addMember(member, to: &members)
        }
        add(TypeFact(name: name, line: TreeWalk.line(node), kind: kind, members: members))
        return name
    }

    /// Adds one class member: a field, or a method with its body's classification.
    ///
    /// - Parameters:
    ///   - member: The class body's child.
    ///   - members: The class's members so far.
    private func addMember(_ member: Node, to members: inout TypeMembers) {
        if Self.fieldTypes.contains(member.nodeType ?? ""), let field = fieldFact(member) {
            members.fields.append(field)
        }
        guard member.nodeType == "method_definition", let name = field(member, "name"), name != "constructor",
              let body = member.child(byFieldName: "body") else { return }
        let statements = TreeWalk.namedChildren(body).filter { $0.nodeType != "comment" }
        Self.addMethod(name, body: Self.classify(statements, throwType: "throw_statement"), to: &members)
    }

    /// Records an interface or enum, with an interface's supertypes and properties.
    ///
    /// - Parameter node: The declaration.
    private func recordType(_ node: Node) {
        let kind: TypeKind = node.nodeType == "interface_declaration" ? .interface : .enum
        guard let name = field(node, "name") else { return }
        var members = TypeMembers(supertypes: heritage(of: node))
        if kind == .interface {
            let body = node.child(byFieldName: "body").map(TreeWalk.namedChildren) ?? []
            members.fields = body.filter { $0.nodeType == "property_signature" }.compactMap(fieldFact)
        }
        add(TypeFact(name: name, line: TreeWalk.line(node), kind: kind, members: members))
    }

    /// Reads a field or property signature, unless it's static.
    ///
    /// - Parameter node: The field.
    /// - Returns: `name:Type` or `name`, or `nil` for a static or computed-name field.
    private func fieldFact(_ node: Node) -> String? {
        let isStatic = (0..<node.childCount).contains { node.child(at: $0)?.nodeType == "static" }
        guard !isStatic, let name = field(node, "name") ?? field(node, "property"),
              name.first.map({ $0.isLetter || $0 == "_" || $0 == "#" }) == true else { return nil }
        return FactText.member(name, type: annotation(node.child(byFieldName: "type")))
    }

    /// Lists the classes and interfaces a declaration extends or implements, extended ones first.
    ///
    /// - Parameter node: The class or interface declaration.
    /// - Returns: Their bare names.
    private func heritage(of node: Node) -> [String] {
        let clauses = TreeWalk.namedChildren(node).filter {
            ["class_heritage", "extends_type_clause", "extends_clause", "implements_clause"].contains($0.nodeType)
        }
        return clauses.flatMap(heritageNames)
    }

    /// Lists the names in one heritage clause, descending into `extends` and `implements` clauses.
    ///
    /// - Parameter clause: A heritage clause, or a type inside one.
    /// - Returns: The bare type names.
    private func heritageNames(_ clause: Node) -> [String] {
        switch clause.nodeType {
        case "class_heritage", "extends_type_clause", "extends_clause", "implements_clause":
            return TreeWalk.namedChildren(clause).flatMap(heritageNames)
        case "type_arguments", "comment":
            return []
        default:
            return text(clause).map { [FactText.typeName($0)] } ?? []
        }
    }

    /// Records a function or method, naming a constructor `<Class>.init`.
    ///
    /// - Parameters:
    ///   - node: The function declaration or method definition.
    ///   - owner: The enclosing class's name.
    private func recordMethod(_ node: Node, _ owner: String?) {
        let name = field(node, "name")
        recordFunction(node, name: name == "constructor" ? (owner ?? "") + ".init" : name)
    }

    /// Records a `const name = () => …` or `function` expression by its variable's name.
    ///
    /// - Parameter node: The variable declarator.
    private func recordFunctionValue(_ node: Node) {
        guard let value = node.child(byFieldName: "value"), Self.functionValues.contains(value.nodeType ?? "") else {
            return
        }
        recordFunction(value, name: field(node, "name"))
    }

    /// Records a function with its parameters.
    ///
    /// - Parameters:
    ///   - node: The function (or method) node.
    ///   - name: Its name.
    private func recordFunction(_ node: Node, name: String?) {
        let list = node.child(byFieldName: "parameters").map(TreeWalk.namedChildren) ?? []
        addFunction(name, node, parameters: list.compactMap(parameter))
    }

    /// Reads one parameter as `name:Type` or `name`.
    ///
    /// - Parameter node: A formal parameter.
    /// - Returns: The parameter, or `nil` for a destructured or rest parameter.
    private func parameter(_ node: Node) -> String? {
        guard Self.parameterTypes.contains(node.nodeType ?? "") else { return nil }
        let pattern = node.child(byFieldName: "pattern") ?? node.child(byFieldName: "left") ?? node
        guard pattern.nodeType == "identifier", let name = text(pattern) else { return nil }
        return FactText.member(name, type: annotation(node.child(byFieldName: "type")))
    }
}
