import SwiftTreeSitter
import BouncerCore

/// PHP: each name a `use` declaration brings in and each literal `require`/`include` path, for the project
/// pass's dependency graph, and the classes, interfaces, traits, enums, and functions a file declares.
///
/// Specifiers keep the form `PHPImportResolver` looks up:
/// - a class, interface, trait, or enum `use` is its fully qualified name without a leading `\`
///   (`App\Models\User`), with a group expanded (`use App\{Foo, Bar\Baz}` is `App\Foo` and `App\Bar\Baz`) and
///   an alias dropped from the specifier (it's the imported name instead);
/// - a `use function` or `use const` keeps its keyword (`function App\Support\helper`,
///   `const App\Support\LIMIT`), so the resolver can map it to its namespace's file;
/// - a `require`, `require_once`, `include`, or `include_once` of a string literal is `require <path>`, and one
///   of `__DIR__` (or `dirname(__FILE__)`) joined to a literal is `require __DIR__<path>`. A path built from
///   variables, constants, or calls isn't recorded.
///
/// The file's own `namespace` isn't recorded: a `use` always names a fully qualified name, so the resolver
/// doesn't need it. HTML outside `<?php … ?>` is `text` in the tree, and declares nothing.
struct PHPModuleFacts: ModuleFactsExtractor {
    /// The `require` and `include` expressions' node types.
    private static let inclusions: Set<String> = [
        "require_expression", "require_once_expression", "include_expression", "include_once_expression"
    ]
    /// Declarations recorded as exports.
    private static let declarations: Set<String> = [
        "class_declaration", "interface_declaration", "trait_declaration", "enum_declaration", "function_definition"
    ]
    /// The node type of a qualified name, such as `App\Models\User`.
    private static let qualifiedName = "qualified_name"
    /// The node type of a plain name.
    private static let plainName = "name"

    /// Extracts PHP imports, exports, and structure.
    ///
    /// - Parameters:
    ///   - root: The parse tree's root.
    ///   - text: Reads a node's source text.
    /// - Returns: The file's `use` and `require` edges, its declarations as exports, and its structure.
    func facts(root: Node, text: (Node) -> String?) -> ModuleFacts {
        var imports: [ImportFact] = []
        TreeWalk.forEach(root) { node in imports += Self.imports(of: node, text: text) }
        let structure = TreeWalk.structure(PHPStructure.self, root: root, text: text)
        return ModuleFacts(imports: imports, exports: Self.exports(in: root, text: text), structure: structure)
    }

    /// Lists the imports one node declares.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - text: Reads a node's source text.
    /// - Returns: A `use` declaration's names, a literal inclusion, or nothing.
    static func imports(of node: Node, text: (Node) -> String?) -> [ImportFact] {
        let type = node.nodeType ?? ""
        if type == "namespace_use_declaration" { return uses(node, text: text) }
        guard inclusions.contains(type), let path = node.namedChild(at: 0).flatMap({ requiredPath($0, text: text) })
        else { return [] }
        return [ImportFact(specifier: "require " + path, line: TreeWalk.line(node))]
    }

    /// Expands a `use` declaration into one import per name, grouped or not.
    ///
    /// - Parameters:
    ///   - node: The `namespace_use_declaration`.
    ///   - text: Reads a node's source text.
    /// - Returns: Each name's import, with its alias or last segment as the imported name.
    private static func uses(_ node: Node, text: (Node) -> String?) -> [ImportFact] {
        let kind = node.child(byFieldName: "type").flatMap(text)
        let prefix = TreeWalk.namedChildren(node).first { $0.nodeType == "namespace_name" }.flatMap(text)
        let clauses = node.child(byFieldName: "body").map(TreeWalk.namedChildren) ?? TreeWalk.namedChildren(node)
        return clauses.filter { $0.nodeType == "namespace_use_clause" }.compactMap { clause in
            use(clause, kind: clause.child(byFieldName: "type").flatMap(text) ?? kind, prefix: prefix, text: text)
        }
    }

    /// Reads one `use` clause.
    ///
    /// - Parameters:
    ///   - clause: The `namespace_use_clause`.
    ///   - kind: `function` or `const` for a function or constant import, else `nil`.
    ///   - prefix: A group's namespace, such as `App` in `use App\{Foo}`.
    ///   - text: Reads a node's source text.
    /// - Returns: The import, or `nil` for a clause without a name.
    private static func use(_ clause: Node, kind: String?, prefix: String?, text: (Node) -> String?) -> ImportFact? {
        let named = TreeWalk.namedChildren(clause).first { [qualifiedName, plainName].contains($0.nodeType) }
        guard let written = named.flatMap(text) else { return nil }
        let full = ([prefix].compactMap { $0 } + [written]).joined(separator: "\\").drop { $0 == "\\" }
        let alias = clause.child(byFieldName: "alias").flatMap(text) ?? lastSegment(of: String(full))
        let specifier = ([kind].compactMap { $0 } + [String(full)]).joined(separator: " ")
        return ImportFact(specifier: specifier, line: TreeWalk.line(clause), names: [alias])
    }

    /// Reads the last segment of a namespaced name.
    ///
    /// - Parameter name: A name such as `App\Models\User`.
    /// - Returns: `User`.
    static func lastSegment(of name: String) -> String {
        name.split(separator: "\\").last.map(String.init) ?? name
    }

    /// Reads a `require` or `include` argument's path, when it's a literal.
    ///
    /// - Parameters:
    ///   - node: The argument.
    ///   - text: Reads a node's source text.
    /// - Returns: The path, `__DIR__`-prefixed when joined to the file's folder, or `nil` for a computed path.
    private static func requiredPath(_ node: Node, text: (Node) -> String?) -> String? {
        switch node.nodeType {
        case "parenthesized_expression": node.namedChild(at: 0).flatMap { requiredPath($0, text: text) }
        case "binary_expression": directoryRelative(node, text: text)
        default: literal(node, text: text)
        }
    }

    /// Reads `__DIR__ . '/path'` or `dirname(__FILE__) . '/path'`.
    ///
    /// - Parameters:
    ///   - node: The concatenation.
    ///   - text: Reads a node's source text.
    /// - Returns: `__DIR__/path`, or `nil` for any other expression.
    private static func directoryRelative(_ node: Node, text: (Node) -> String?) -> String? {
        let left = node.child(byFieldName: "left").flatMap(text)?.filter { !$0.isWhitespace }
        guard left == "__DIR__" || left == "dirname(__FILE__)",
              let path = node.child(byFieldName: "right").flatMap({ literal($0, text: text) }) else { return nil }
        return "__DIR__" + path
    }

    /// Reads a string literal without interpolation.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - text: Reads a node's source text.
    /// - Returns: The string's contents, or `nil` for anything else or a string with variables in it.
    private static func literal(_ node: Node, text: (Node) -> String?) -> String? {
        guard ["string", "encapsed_string"].contains(node.nodeType),
              TreeWalk.namedChildren(node).allSatisfy({ $0.nodeType == "string_content" }),
              let written = text(node) else { return nil }
        let path = TreeWalk.unquote(written)
        return path.isEmpty ? nil : path
    }

    /// Lists the classes, interfaces, traits, enums, and functions a file declares, at the top level or inside
    /// a namespace or a conditional, but not inside a function body.
    ///
    /// - Parameters:
    ///   - node: The subtree's root.
    ///   - text: Reads a node's source text.
    /// - Returns: Each declaration's name and line.
    static func exports(in node: Node, text: (Node) -> String?) -> [ExportFact] {
        guard declarations.contains(node.nodeType ?? "") else {
            return TreeWalk.namedChildren(node).flatMap { exports(in: $0, text: text) }
        }
        return node.child(byFieldName: "name").flatMap(text).map { [ExportFact(name: $0, line: TreeWalk.line(node))] }
            ?? []
    }
}

/// Collects PHP structure facts: classes (abstract or not), interfaces, traits, and enums with their
/// supertypes, properties, and methods; and functions and methods with bodies, with their parameters.
final class PHPStructure: StructureCollector {
    /// Each type declaration's kind; a trait is reused code rather than an abstraction, so it's `.other`.
    private static let kinds: [String: TypeKind] = [
        "class_declaration": .class, "interface_declaration": .interface, "trait_declaration": .other,
        "enum_declaration": .enum
    ]
    /// The clauses naming a type's superclass (`extends`) and interfaces (`implements`).
    private static let supertypeClauses: Set<String> = ["base_clause", "class_interface_clause"]
    /// The parameter node types that name a variable.
    private static let parameterTypes: Set<String> = [
        "simple_parameter", "variadic_parameter", "property_promotion_parameter"
    ]

    /// Records a declaration by its node type.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - owner: The enclosing type's name, if any.
    /// - Returns: A type's own name, for its methods; otherwise `owner`.
    override func record(_ node: Node, owner: String?) -> String? {
        let type = node.nodeType ?? ""
        if Self.kinds[type] != nil { return recordType(node) ?? owner }
        if type == "function_definition" { recordFunction(node, owner: nil) }
        if type == "method_declaration", node.child(byFieldName: "body") != nil { recordFunction(node, owner: owner) }
        return owner
    }

    /// Records a type with its kind and members.
    ///
    /// - Parameter node: The type declaration.
    /// - Returns: The type's name, or `nil` without one.
    private func recordType(_ node: Node) -> String? {
        guard let name = field(node, "name"), let kind = Self.kinds[node.nodeType ?? ""] else { return nil }
        let children = TreeWalk.namedChildren(node)
        let isAbstract = children.contains { $0.nodeType == "abstract_modifier" }
        add(TypeFact(name: name, line: TreeWalk.line(node), kind: isAbstract ? .abstractClass : kind,
                     members: members(of: node, children: children)))
        return name
    }

    /// Reads a type's supertypes, properties, and declared methods.
    ///
    /// - Parameters:
    ///   - node: The type declaration.
    ///   - children: Its named children.
    /// - Returns: Its members.
    private func members(of node: Node, children: [Node]) -> TypeMembers {
        let body = node.child(byFieldName: "body").map(TreeWalk.namedChildren) ?? []
        var facts = TypeMembers(supertypes: children.filter { Self.supertypeClauses.contains($0.nodeType ?? "") }
            .flatMap(TreeWalk.namedChildren).compactMap(text))
        facts.fields = body.filter { $0.nodeType == "property_declaration" }.flatMap(properties)
        facts.methods = body.filter { $0.nodeType == "method_declaration" }.compactMap { field($0, "name") }
        return facts
    }

    /// Lists a property declaration's properties, as `name:Type`.
    ///
    /// - Parameter node: The `property_declaration`.
    /// - Returns: Each property, without its `$`.
    private func properties(_ node: Node) -> [String] {
        let type = field(node, "type")
        return TreeWalk.namedChildren(node).filter { $0.nodeType == "property_element" }.compactMap { element in
            variable(element.child(byFieldName: "name")).map { FactText.member($0, type: type) }
        }
    }

    /// Records a function or method with its parameter names; a constructor is `<Type>.init`.
    ///
    /// - Parameters:
    ///   - node: The function or method.
    ///   - owner: The enclosing type, for a method.
    private func recordFunction(_ node: Node, owner: String?) {
        let list = node.child(byFieldName: "parameters").map(TreeWalk.namedChildren) ?? []
        let parameters = list.filter { Self.parameterTypes.contains($0.nodeType ?? "") }
            .compactMap { variable($0.child(byFieldName: "name")) }
        let name = field(node, "name").map { $0 == "__construct" ? (owner ?? "") + ".init" : $0 }
        addFunction(name, node, parameters: parameters, owner: owner, returns: field(node, "return_type"))
    }

    /// Reads a variable's name without its `$`.
    ///
    /// - Parameter node: A `variable_name`, or `nil`.
    /// - Returns: The name, or `nil`.
    private func variable(_ node: Node?) -> String? {
        node.flatMap(text).map { String($0.drop { $0 == "$" || $0 == "&" }) }
    }
}
