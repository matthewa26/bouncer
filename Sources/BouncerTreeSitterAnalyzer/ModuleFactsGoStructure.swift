import SwiftTreeSitter
import BouncerCore

/// Collects Go structure facts: struct, interface, and other named types; functions and methods; and
/// `switch` subjects. Go has no inheritance, so types carry no supertypes.
final class GoStructure: StructureCollector {
    private static let kinds: [String: TypeKind] = ["struct_type": .struct, "interface_type": .interface]

    /// Records a declaration by its node type.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - owner: Unused; Go methods aren't nested in their types.
    /// - Returns: `owner`.
    override func record(_ node: Node, owner: String?) -> String? {
        switch node.nodeType {
        case "type_spec": recordType(node)
        case "function_declaration", "method_declaration": recordFunction(node)
        case "expression_switch_statement": addSwitch(node.child(byFieldName: "value"), node)
        case "type_switch_statement": addSwitch(node.child(byFieldName: "value"), node, suffix: ".(type)")
        default: break
        }
        return owner
    }

    /// Records a named type, with a struct's fields.
    ///
    /// - Parameter node: The type spec.
    private func recordType(_ node: Node) {
        guard let name = field(node, "name"), let type = node.child(byFieldName: "type") else { return }
        let kind = Self.kinds[type.nodeType ?? ""] ?? .other
        let fields = kind == .struct ? structFields(type) : []
        add(TypeFact(name: name, line: TreeWalk.line(node), kind: kind, members: TypeMembers(fields: fields)))
    }

    /// Lists a struct's named fields, leaving out embedded ones.
    ///
    /// - Parameter type: The struct type.
    /// - Returns: Each field as `name:Type`.
    private func structFields(_ type: Node) -> [String] {
        let list = TreeWalk.namedChildren(type).first { $0.nodeType == "field_declaration_list" }
        let declarations = list.map(TreeWalk.namedChildren)?.filter { $0.nodeType == "field_declaration" } ?? []
        return declarations.flatMap { named($0, nameType: "field_identifier") }
    }

    /// Records a function or method with its parameters.
    ///
    /// - Parameter node: The declaration.
    private func recordFunction(_ node: Node) {
        let list = node.child(byFieldName: "parameters").map(TreeWalk.namedChildren) ?? []
        let parameters = list.filter { $0.nodeType == "parameter_declaration" }.flatMap {
            named($0, nameType: "identifier")
        }
        addFunction(field(node, "name"), node, parameters: parameters)
    }

    /// Reads a declaration that names several things of one type, such as `a, b int`.
    ///
    /// - Parameters:
    ///   - node: The field or parameter declaration.
    ///   - nameType: The node type of its names.
    /// - Returns: Each name as `name:Type`.
    private func named(_ node: Node, nameType: String) -> [String] {
        let type = field(node, "type")
        return TreeWalk.namedChildren(node).filter { $0.nodeType == nameType }.compactMap(text).map {
            FactText.member($0, type: type)
        }
    }
}
