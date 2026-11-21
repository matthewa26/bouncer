import SwiftTreeSitter
import BouncerCore

/// Rust: each `mod name;` declaration and each path a `use` brings in, for the project pass's dependency graph.
///
/// A `mod` declaration is recorded as `mod name`, or `mod outer::name` inside an inline `mod outer { … }`, so the
/// resolver can find the file that holds it. A `use` is recorded once per path it names, with a use list
/// expanded (`use crate::a::{b, c::d}` is `crate::a::b` and `crate::a::c::d`) and an alias or glob dropped. A
/// path relative to the current module (`self::…`, `super::…`) inside an inline module is prefixed with that
/// module, as `self::outer::super::x`, so it resolves from the right place.
struct RustModuleFacts: ModuleFactsExtractor {
    /// The path segment naming the parent module.
    private static let superSegment = "super"

    /// Extracts Rust module declarations, imports, and structure.
    ///
    /// - Parameters:
    ///   - root: The parse tree's root.
    ///   - text: Reads a node's source text.
    /// - Returns: The file's module edges and declared types; `pub` items aren't recorded as exports.
    func facts(root: Node, text: (Node) -> String?) -> ModuleFacts {
        let imports = TreeWalk.imports(in: root) { Self.specifiers(of: $0, text: text) }
        return ModuleFacts(imports: imports, structure: TreeWalk.structure(RustStructure.self, root: root, text: text))
    }

    /// Lists the module specifiers one node declares.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - text: Reads a node's source text.
    /// - Returns: `mod …` for an out-of-line module, each path of a `use`, or nothing.
    static func specifiers(of node: Node, text: (Node) -> String?) -> [String] {
        switch node.nodeType {
        case "mod_item": moduleDeclaration(node, text: text).map { [$0] } ?? []
        case "use_declaration":
            node.child(byFieldName: "argument").map { argument in
                let inline = inlineModules(around: node, text: text)
                return usePaths(argument, prefix: "", text: text).map { relative($0, inline: inline) }
            } ?? []
        default: []
        }
    }

    /// Reads an out-of-line `mod name;` declaration.
    ///
    /// - Parameters:
    ///   - node: A module item.
    ///   - text: Reads a node's source text.
    /// - Returns: `mod name` with any enclosing inline modules, or `nil` for an inline `mod name { … }`.
    private static func moduleDeclaration(_ node: Node, text: (Node) -> String?) -> String? {
        guard node.child(byFieldName: "body") == nil, let name = node.child(byFieldName: "name").flatMap(text)
        else { return nil }
        return "mod " + (inlineModules(around: node, text: text) + [name]).joined(separator: "::")
    }

    /// Names the inline modules enclosing a node, outermost first.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - text: Reads a node's source text.
    /// - Returns: The names of every `mod name { … }` around it.
    private static func inlineModules(around node: Node, text: (Node) -> String?) -> [String] {
        var names: [String] = [], current = node.parent
        while let parent = current {
            if parent.nodeType == "mod_item", let name = parent.child(byFieldName: "name").flatMap(text) {
                names.insert(name, at: 0)
            }
            current = parent.parent
        }
        return names
    }

    /// Rewrites a `self::`/`super::` path inside inline modules relative to the file's own module: each leading
    /// `super` climbs out of one inline module, and what's left is prefixed with the inline modules still around it.
    ///
    /// - Parameters:
    ///   - path: The `use` path.
    ///   - inline: The inline modules around the `use`, outermost first.
    /// - Returns: The path relative to the file's module, as `self::outer::x`, or unchanged when not nested.
    private static func relative(_ path: String, inline: [String]) -> String {
        var parts = path.components(separatedBy: "::"), enclosing = inline
        guard !enclosing.isEmpty, parts.first == "self" || parts.first == superSegment else { return path }
        while parts.first == superSegment, !enclosing.isEmpty {
            parts.removeFirst()
            enclosing.removeLast()
        }
        if parts.first == superSegment { return parts.joined(separator: "::") }
        return (["self"] + enclosing + parts.drop { $0 == "self" }).joined(separator: "::")
    }

    /// Expands one `use` argument into the paths it names.
    ///
    /// - Parameters:
    ///   - node: The argument: a path, an aliased path, a glob, or a (scoped) use list.
    ///   - prefix: The path the enclosing use list sits under, with its trailing `::`.
    ///   - text: Reads a node's source text.
    /// - Returns: Each named path in full.
    private static func usePaths(_ node: Node, prefix: String, text: (Node) -> String?) -> [String] {
        switch node.nodeType {
        case "use_as_clause": node.child(byFieldName: "path").flatMap(text).map { [prefix + $0] } ?? []
        case "use_wildcard": node.namedChild(at: 0).flatMap(text).map { [prefix + $0] } ?? [prefix + "*"]
        case "use_list": TreeWalk.namedChildren(node).flatMap { usePaths($0, prefix: prefix, text: text) }
        case "scoped_use_list": scopedPaths(node, prefix: prefix, text: text)
        default: text(node).map { [prefix + $0] } ?? []
        }
    }

    /// Expands a scoped use list, such as `a::b::{c, d}`, under its path.
    ///
    /// - Parameters:
    ///   - node: The scoped use list.
    ///   - prefix: The path the enclosing use list sits under, with its trailing `::`.
    ///   - text: Reads a node's source text.
    /// - Returns: Each named path in full.
    private static func scopedPaths(_ node: Node, prefix: String, text: (Node) -> String?) -> [String] {
        let path = node.child(byFieldName: "path").flatMap(text).map { prefix + $0 + "::" } ?? prefix
        return node.child(byFieldName: "list").map { usePaths($0, prefix: path, text: text) } ?? []
    }
}

/// Collects Rust structure facts: structs with their fields, enums, and traits with their methods; and
/// functions, with an `impl` block's methods owned by the type it implements.
final class RustStructure: StructureCollector {
    private static let kinds: [String: TypeKind] = [
        "struct_item": .struct, "union_item": .struct, "enum_item": .enum, "trait_item": .protocol
    ]

    /// Records a declaration by its node type.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - owner: The type the enclosing `impl` block implements, if any.
    /// - Returns: The type an `impl` block implements, for its methods; otherwise `owner`.
    override func record(_ node: Node, owner: String?) -> String? {
        let type = node.nodeType ?? ""
        if type == "impl_item" { return node.child(byFieldName: "type").flatMap(text).map(FactText.typeName) }
        if Self.kinds[type] != nil { recordType(node) }
        if type == "function_item" { recordFunction(node, owner: owner) }
        return owner
    }

    /// Records a struct's fields, or a trait's declared methods.
    ///
    /// - Parameter node: The type declaration.
    private func recordType(_ node: Node) {
        guard let name = field(node, "name"), let kind = Self.kinds[node.nodeType ?? ""] else { return }
        let members = node.child(byFieldName: "body").map(TreeWalk.namedChildren) ?? []
        var facts = TypeMembers(fields: members.filter { $0.nodeType == "field_declaration" }.compactMap { member in
            field(member, "name").map { FactText.member($0, type: field(member, "type")) }
        })
        facts.methods = members.filter { ["function_item", "function_signature_item"].contains($0.nodeType) }
            .compactMap { field($0, "name") }
        add(TypeFact(name: name, line: TreeWalk.line(node), kind: kind, members: facts))
    }

    /// Records a function or method with its parameter names, leaving out `self`.
    ///
    /// - Parameters:
    ///   - node: The function.
    ///   - owner: The implemented type, for a method.
    private func recordFunction(_ node: Node, owner: String?) {
        let list = node.child(byFieldName: "parameters").map(TreeWalk.namedChildren) ?? []
        let parameters = list.filter { $0.nodeType == "parameter" }.compactMap { field($0, "pattern") }
        let returns = field(node, "return_type")
        addFunction(field(node, "name"), node, parameters: parameters, owner: owner, returns: returns)
    }
}
