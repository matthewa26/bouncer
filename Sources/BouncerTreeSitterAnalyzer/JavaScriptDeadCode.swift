import Foundation
import SwiftTreeSitter
import BouncerCore
import BouncerRules

/// TypeScript and JavaScript dead code: unexported top-level declarations, import bindings, and
/// parameters nothing in the file uses.
///
/// JSX tags, type positions, `export { x }`, and `export default x` all count as uses, as do names in
/// JSDoc `{Type}` braces and an `@jsx` pragma; a file with JSX also uses `React`, for the classic runtime.
/// Unexported declarations are only checked in modules, since a script's top-level names are global.
struct JavaScriptDeadCode: DeadCodeExtractor {
    private static let identifierType = "identifier"
    private static let useTypes: Set<String> = [identifierType, "type_identifier", "shorthand_property_identifier"]
    private static let jsxTypes: Set<String> = ["jsx_opening_element", "jsx_self_closing_element"]
    private static let moduleExtensions: Set<String> = ["mjs", "cjs", "mts", "cts"]
    private static let declarationDetails: [String: String] = [
        "function_declaration": "Unexported function", "generator_function_declaration": "Unexported function",
        "class_declaration": "Unexported class", "abstract_class_declaration": "Unexported class"
    ]
    private static let jsdocPattern = try? NSRegularExpression(pattern: "\\{[^}]*\\}|@jsx(?:Frag)?\\s+\\w+")
    private static let wordPattern = try? NSRegularExpression(pattern: "[A-Za-z_$][A-Za-z0-9_$]*")

    /// Lists a file's unused unexported declarations, imports, and parameters; `.d.ts` files have none.
    ///
    /// - Parameter tree: The parsed file.
    /// - Returns: Its unused declarations.
    func unusedDeclarations(in tree: DeadCodeTree) -> [UnusedDeclaration] {
        guard !tree.fileName.hasSuffix(".d.ts") else { return [] }
        let uses = UseIndex(tree, types: Self.useTypes) { extraUses(of: $0, tree: tree) }
        let symbols = isModule(tree, uses: uses) ? unexportedSymbols(tree, uses: uses) : []
        return symbols + unusedImports(tree, uses: uses)
            + JavaScriptParameters(tree: tree, uses: uses).unusedParameters()
    }

    /// Reports whether a file is a module, whose top-level names are its own rather than global.
    ///
    /// - Parameters:
    ///   - tree: The parsed file.
    ///   - uses: The file's name uses.
    /// - Returns: Whether it imports, exports, uses CommonJS, or has a module-only extension.
    private func isModule(_ tree: DeadCodeTree, uses: UseIndex) -> Bool {
        let statements = Set(TreeWalk.namedChildren(tree.root).compactMap(\.nodeType))
        let usesCommonJS = ["require", "module", "exports"].contains(where: uses.contains)
        let fileExtension = URL(fileURLWithPath: tree.fileName).pathExtension.lowercased()
        return !statements.isDisjoint(with: ["import_statement", "export_statement"]) || usesCommonJS
            || Self.moduleExtensions.contains(fileExtension)
    }

    /// Lists the names a node uses without an identifier: `React` for JSX, and words in JSDoc braces.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - tree: The parsed file.
    /// - Returns: The names it uses.
    private func extraUses(of node: Node, tree: DeadCodeTree) -> [String] {
        if let type = node.nodeType, Self.jsxTypes.contains(type) { return ["React"] }
        guard node.nodeType == "comment", let comment = tree.text(node), comment.hasPrefix("/**") else { return [] }
        return Self.matches(of: Self.jsdocPattern, in: comment).flatMap { Self.matches(of: Self.wordPattern, in: $0) }
    }

    /// Lists every match of a pattern in a string.
    ///
    /// - Parameters:
    ///   - pattern: The pattern, or `nil` if it failed to compile.
    ///   - string: The string to search.
    /// - Returns: Each match's text.
    private static func matches(of pattern: NSRegularExpression?, in string: String) -> [String] {
        let found = pattern?.matches(in: string, range: NSRange(string.startIndex..., in: string)) ?? []
        return found.compactMap { Range($0.range, in: string).map { String(string[$0]) } }
    }

    /// Lists unexported top-level functions, classes, and variables nothing outside them uses.
    ///
    /// - Parameters:
    ///   - tree: The parsed file.
    ///   - uses: The file's name uses.
    /// - Returns: The unused declarations.
    private func unexportedSymbols(_ tree: DeadCodeTree, uses: UseIndex) -> [UnusedDeclaration] {
        let declared = TreeWalk.namedChildren(tree.root).flatMap { declarations(in: $0, tree: tree) }
        return declared.compactMap { name, node, detail in
            guard !name.hasPrefix("_"), !uses.isUsed(name, outside: node.byteRange) else { return nil }
            return tree.unused(.privateSymbol, name, at: node, detail: detail)
        }
    }

    /// Lists the names one top-level statement declares, with the node each declaration spans.
    ///
    /// - Parameters:
    ///   - statement: A top-level statement; `export` statements declare nothing private.
    ///   - tree: The parsed file.
    /// - Returns: Each simple name, its declaring node, and what it is.
    private func declarations(in statement: Node, tree: DeadCodeTree) -> [(String, Node, String)] {
        let type = statement.nodeType ?? ""
        if let detail = Self.declarationDetails[type] {
            return tree.text(statement, field: "name").map { [($0, statement, detail)] } ?? []
        }
        guard type == "lexical_declaration" || type == "variable_declaration" else { return [] }
        return TreeWalk.namedChildren(statement).filter { $0.nodeType == "variable_declarator" }.compactMap { node in
            guard node.child(byFieldName: "name")?.nodeType == Self.identifierType else { return nil }
            return tree.text(node, field: "name").map { ($0, node, "Unexported variable") }
        }
    }

    /// Lists import bindings nothing outside their import statement uses; side-effect imports bind none.
    ///
    /// - Parameters:
    ///   - tree: The parsed file.
    ///   - uses: The file's name uses.
    /// - Returns: The unused imports.
    private func unusedImports(_ tree: DeadCodeTree, uses: UseIndex) -> [UnusedDeclaration] {
        TreeWalk.namedChildren(tree.root).filter { $0.nodeType == "import_statement" }.flatMap { statement in
            bindings(of: statement).compactMap { binding in
                guard let name = tree.text(binding) else { return nil }
                guard !uses.isUsed(name, outside: statement.byteRange) else { return nil }
                return tree.unused(.importBinding, name, at: binding, detail: "import")
            }
        }
    }

    /// Lists the identifiers an import statement binds: its default, namespace, and named imports.
    ///
    /// - Parameter statement: The import statement.
    /// - Returns: The binding identifiers; none for a side-effect import, which has no clause.
    private func bindings(of statement: Node) -> [Node] {
        var found: [Node] = []
        let clause = TreeWalk.namedChildren(statement).first { $0.nodeType == "import_clause" }
        clause.map { TreeWalk.forEach($0) { node in binding(node).map { found.append($0) } } }
        return found
    }

    /// Reads the identifier one node inside an import clause binds, if it binds one.
    ///
    /// - Parameter node: A node inside the clause.
    /// - Returns: A default or namespace import's identifier, a named import's alias or name, or `nil`.
    private func binding(_ node: Node) -> Node? {
        switch node.nodeType {
        case Self.identifierType where ["import_clause", "namespace_import"].contains(node.parent?.nodeType ?? ""):
            return node
        case "import_specifier":
            return node.child(byFieldName: "alias") ?? node.child(byFieldName: "name")
        default:
            return nil
        }
    }
}
