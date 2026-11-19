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
        Self.addMethod(name, body: Self.classify(statements, throwType: "throw_statement"), to: &members,
                       guarded: isGuarded(member, name: name, statements: statements))
    }

    /// Reports whether a public method opens with a precondition on its arguments before more code.
    ///
    /// - Parameters:
    ///   - method: The method definition.
    ///   - name: Its name.
    ///   - statements: Its body's statements.
    /// - Returns: Whether its first statement narrows what it accepts.
    private func isGuarded(_ method: Node, name: String, statements: [Node]) -> Bool {
        let list = method.child(byFieldName: "parameters").map(TreeWalk.namedChildren) ?? []
        let arguments = Set(list.compactMap(parameter).map { String($0.prefix { $0 != ":" }) })
        guard statements.count > 1, !Self.isPrivate(name) else { return false }
        return isArgumentGuard(statements[0], throwType: "throw_statement", arguments: arguments)
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
            members.methods = body.filter { $0.nodeType == "method_signature" }.compactMap { field($0, "name") }
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
        let methodOwner = node.nodeType == "method_definition" ? owner : nil
        recordFunction(node, name: name == "constructor" ? (owner ?? "") + ".init" : name, owner: methodOwner)
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

    /// Records a function with its parameters and return type.
    ///
    /// - Parameters:
    ///   - node: The function (or method) node.
    ///   - name: Its name.
    ///   - owner: The class it's a method of, if any.
    private func recordFunction(_ node: Node, name: String?, owner: String? = nil) {
        let list = node.child(byFieldName: "parameters").map(TreeWalk.namedChildren) ?? []
        let returns = annotation(node.child(byFieldName: "return_type"))
        addFunction(name, node, parameters: list.compactMap(parameter), owner: owner, returns: returns)
    }

    /// Notes a typed name, a member read, or a construction inside a class.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - builder: The class's collaboration facts.
    override func collaborate(_ node: Node, _ builder: CollaborationBuilder) {
        switch node.nodeType {
        case "public_field_definition", "field_definition": bindTyped(node, nameField: "name", builder, kept: true)
        case "required_parameter", "optional_parameter": bindTyped(node, nameField: "pattern", builder)
        case "variable_declarator": bindTyped(node, nameField: "name", builder)
        case "assignment_expression": bindAssigned(node, builder)
        case "member_expression": noteRead(node, builder)
        default: break
        }
    }

    /// Binds a declared name to its type annotation, or to the class its value constructs.
    ///
    /// - Parameters:
    ///   - node: A field, parameter, or variable declarator.
    ///   - nameField: The field holding its name.
    ///   - builder: The class's collaboration facts.
    ///   - kept: Whether it's a class field, which keeps what its value constructs.
    private func bindTyped(_ node: Node, nameField: String, _ builder: CollaborationBuilder, kept: Bool = false) {
        guard let name = field(node, nameField) else { return }
        let written = annotation(node.child(byFieldName: "type")).map(FactText.typeName)
        let constructed = node.child(byFieldName: "value").flatMap(constructed)
        if let type = written ?? constructed { builder.bind(name, type) }
        if kept, let constructed { builder.construct(constructed) }
    }

    /// Binds `this.name = new Foo()` and `name = new Foo()`, recording the first as a kept construction.
    ///
    /// - Parameters:
    ///   - node: The assignment.
    ///   - builder: The class's collaboration facts.
    private func bindAssigned(_ node: Node, _ builder: CollaborationBuilder) {
        guard let left = node.child(byFieldName: "left"), let name = receiverName(left),
              let type = node.child(byFieldName: "right").flatMap(constructed) else { return }
        builder.bind(name, type)
        if left.nodeType == "member_expression" { builder.construct(type) }
    }

    /// Notes `name.member` or `this.name.member`.
    ///
    /// - Parameters:
    ///   - node: The member expression.
    ///   - builder: The class's collaboration facts.
    private func noteRead(_ node: Node, _ builder: CollaborationBuilder) {
        guard let object = node.child(byFieldName: "object"), let base = receiverName(object),
              let member = field(node, "property") else { return }
        builder.access(base, member)
    }

    /// Names the value an expression reads: a bare identifier, or `this.name`.
    ///
    /// - Parameter node: The expression.
    /// - Returns: The name, or `nil` for anything else.
    private func receiverName(_ node: Node) -> String? {
        if node.nodeType == "identifier" { return text(node) }
        guard node.nodeType == "member_expression", node.child(byFieldName: "object")?.nodeType == "this" else {
            return nil
        }
        return field(node, "property")
    }

    /// Names the class a `new` expression constructs.
    ///
    /// - Parameter node: The expression.
    /// - Returns: The class's bare name, or `nil` if it isn't `new` of a name.
    private func constructed(_ node: Node) -> String? {
        guard node.nodeType == "new_expression", let callee = node.child(byFieldName: "constructor"),
              ["identifier", "member_expression"].contains(callee.nodeType) else { return nil }
        return text(callee).map(FactText.typeName)
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
