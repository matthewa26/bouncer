import SwiftTreeSitter

/// How a C-family grammar lays out declarations that carry no `name`, `body`, or `parameters` field.
///
/// A C function names itself and lists its parameters inside nested declarators (`int *f(int a)`), and an
/// Objective-C method, class, or category keeps its selector parts, body, and members as plain children.
/// The summary builder and quality collector fall back to this when the usual fields are absent.
struct CDeclarationSpec: Sendable { // bouncer:disable-line lack-of-cohesion -- grammar data, one part per reader
    /// The field a C function's name and parameter list nest under.
    var declaratorField = "declarator"
    /// Methods named by their selector: each keyword identifier, followed by `:` when it takes an argument.
    let selectorMethodNodeTypes: Set<String>
    /// A selector method's argument entries, such as `:(int)a`.
    let selectorParameterNodeType: String
    /// The block that is a function's or method's body when no `body` field holds it.
    let bodyNodeType: String
    /// Type declarations whose members are their own children, such as `@interface … @end`.
    let typeNodeTypes: Set<String>
    /// The field naming a category (`@interface Widget (Extras)`), appended to the type's name in parentheses.
    let categoryField: String
    /// A type's method members, as its direct children or one level inside a wrapper below.
    let methodMemberNodeTypes: Set<String>
    /// A type's field members (properties and instance variables), found the same way.
    let fieldMemberNodeTypes: Set<String>
    /// Children of a type that hold members rather than being one, such as `implementation_definition`.
    let memberWrapperNodeTypes: Set<String>
    /// The storage class keyword that keeps a C function private to its file.
    let fileScopeKeyword: String
    /// The share of declarations that may fail to parse before the file goes to the fallback analyzer, or
    /// `nil` to always analyze the tree.
    var maxErrorShare: Double?

    /// Reads a function's or method's body: its first child of the body block type.
    ///
    /// - Parameter node: The function or method node.
    /// - Returns: The body, or `nil` for a declaration without one.
    func body(of node: Node) -> Node? {
        TreeWalk.namedChildren(node).first { $0.nodeType == bodyNodeType }
    }

    /// Names a function or method: a selector such as `foo:bar:`, or the identifier inside a C declarator.
    ///
    /// - Parameters:
    ///   - node: The function or method node.
    ///   - text: Reads a node's source text.
    /// - Returns: The name, or `nil` if none can be read.
    func name(of node: Node, text: (Node) -> String?) -> String? {
        guard selectorMethodNodeTypes.contains(node.nodeType ?? "") else {
            return innermostDeclarator(of: node).flatMap(text)
        }
        let parts = TreeWalk.namedChildren(node).compactMap { child -> String? in
            if child.nodeType == selectorParameterNodeType { return ":" }
            return child.nodeType == "identifier" ? text(child) : nil
        }
        return parts.isEmpty ? nil : parts.joined()
    }

    /// Lists a function's or method's parameter entries.
    ///
    /// - Parameter node: The function or method node.
    /// - Returns: A method's selector arguments, a C function's parameter declarations, or `nil` when the
    ///   node is neither, so the caller reads its `parameters` field as usual.
    func parameters(of node: Node) -> [Node]? {
        if selectorMethodNodeTypes.contains(node.nodeType ?? "") {
            return TreeWalk.namedChildren(node).filter { $0.nodeType == selectorParameterNodeType }
        }
        guard node.child(byFieldName: declaratorField) != nil else { return nil }
        var current = node.child(byFieldName: declaratorField)
        while let declarator = current, declarator.child(byFieldName: "parameters") == nil {
            current = declarator.child(byFieldName: declaratorField)
        }
        return current?.child(byFieldName: "parameters").map(TreeWalk.namedChildren) ?? []
    }

    /// Names a type: its first identifier, with a category's name in parentheses, as in `Widget(Extras)`.
    ///
    /// - Parameters:
    ///   - node: The type node.
    ///   - text: Reads a node's source text.
    /// - Returns: The name, or `nil` if the node has no identifier.
    func typeName(of node: Node, text: (Node) -> String?) -> String? {
        guard let name = TreeWalk.namedChildren(node).first(where: { $0.nodeType == "identifier" }).flatMap(text)
        else { return nil }
        guard let category = node.child(byFieldName: categoryField).flatMap(text) else { return name }
        return name + "(" + category + ")"
    }

    /// Lists a type's members: its member children, with wrappers like `implementation_definition` opened.
    ///
    /// - Parameter type: The type node.
    /// - Returns: The methods, properties, and instance variables it declares.
    func members(of type: Node) -> [Node] {
        let memberTypes = methodMemberNodeTypes.union(fieldMemberNodeTypes)
        return TreeWalk.namedChildren(type).flatMap { child in
            memberWrapperNodeTypes.contains(child.nodeType ?? "") ? TreeWalk.namedChildren(child) : [child]
        }.filter { memberTypes.contains($0.nodeType ?? "") }
    }

    /// Reports whether a C function is declared `static`, so only its own file can call it.
    ///
    /// - Parameters:
    ///   - node: The function node.
    ///   - text: Reads a node's source text.
    /// - Returns: Whether a storage class specifier makes it file-scoped.
    func isFileScoped(_ node: Node, text: (Node) -> String?) -> Bool {
        TreeWalk.namedChildren(node).contains {
            $0.nodeType == "storage_class_specifier" && text($0) == fileScopeKeyword
        }
    }

    /// Follows a declaration's nested declarators to the identifier they declare.
    ///
    /// - Parameter node: The declaration.
    /// - Returns: The innermost declarator, or `nil` without one.
    private func innermostDeclarator(of node: Node) -> Node? {
        var current = node.child(byFieldName: declaratorField)
        while let declarator = current, let inner = declarator.child(byFieldName: declaratorField) {
            current = inner
        }
        return current
    }
}
