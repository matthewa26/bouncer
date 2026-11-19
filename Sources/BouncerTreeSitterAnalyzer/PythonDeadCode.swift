import SwiftTreeSitter
import BouncerCore
import BouncerRules

/// Python dead code: `_`-prefixed module-level functions and classes, import bindings, and parameters
/// nothing in the file uses.
///
/// Names listed in `__all__` and words in string annotations such as `x: "Model"` count as uses.
/// `__init__.py` files re-export by importing, so their imports are never flagged, nor are
/// `from __future__` imports, star imports, or imports marked `# noqa`. Public-named functions may be
/// imported elsewhere, so only `_`-prefixed ones are checked.
struct PythonDeadCode: DeadCodeExtractor {
    private static let definitionDetails = [
        "function_definition": "Private function", "class_definition": "Private class"
    ]

    /// Lists a file's unused private definitions, imports, and parameters.
    ///
    /// - Parameter tree: The parsed file.
    /// - Returns: Its unused declarations.
    func unusedDeclarations(in tree: DeadCodeTree) -> [UnusedDeclaration] {
        let uses = UseIndex(tree, types: ["identifier"]) { stringUses(of: $0, tree: tree) }
        let imports = tree.fileName == "__init__.py" ? [] : unusedImports(tree, uses: uses)
        let parameters = PythonParameters(tree: tree, uses: uses).unusedParameters()
        return privateDefinitions(tree, uses: uses) + imports + parameters
    }

    /// Lists the names a string uses: each word of an annotation string, or the name an `__all__` entry lists.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - tree: The parsed file.
    /// - Returns: The names it uses.
    private func stringUses(of node: Node, tree: DeadCodeTree) -> [String] {
        guard node.nodeType == "string_content", let text = tree.text(node) else { return [] }
        let isListed = DeadCodeNodes.ancestor(of: node) { ancestor in
            ["assignment", "augmented_assignment"].contains(ancestor.nodeType ?? "")
                && tree.text(ancestor, field: "left") == "__all__"
        } != nil
        let isAnnotation = DeadCodeNodes.ancestor(of: node) { $0.nodeType == "type" } != nil
        guard isListed || isAnnotation else { return [] }
        return text.split { !($0.isLetter || $0.isNumber || $0 == "_") }.map(String.init)
    }

    /// Lists `_`-prefixed module-level functions and classes nothing outside them uses; dunders are exempt.
    ///
    /// - Parameters:
    ///   - tree: The parsed file.
    ///   - uses: The file's name uses.
    /// - Returns: The unused definitions.
    private func privateDefinitions(_ tree: DeadCodeTree, uses: UseIndex) -> [UnusedDeclaration] {
        TreeWalk.namedChildren(tree.root).compactMap { statement in
            let definition = statement.nodeType == "decorated_definition"
                ? statement.child(byFieldName: "definition") : statement
            guard let definition, let detail = Self.definitionDetails[definition.nodeType ?? ""],
                  let name = tree.text(definition, field: "name"), Self.isPrivate(name),
                  !uses.isUsed(name, outside: statement.byteRange) else { return nil }
            return tree.unused(.privateSymbol, name, at: definition, detail: detail)
        }
    }

    /// Reports whether a name is private by convention: a leading `_`, but not a `__dunder__`.
    ///
    /// - Parameter name: The name.
    /// - Returns: Whether it's private.
    private static func isPrivate(_ name: String) -> Bool {
        name.hasPrefix("_") && !(name.hasPrefix("__") && name.hasSuffix("__"))
    }

    /// Lists import bindings nothing outside their import statement uses.
    ///
    /// - Parameters:
    ///   - tree: The parsed file.
    ///   - uses: The file's name uses.
    /// - Returns: The unused imports.
    private func unusedImports(_ tree: DeadCodeTree, uses: UseIndex) -> [UnusedDeclaration] {
        var found: [UnusedDeclaration] = []
        TreeWalk.forEach(tree.root) { statement in
            guard ["import_statement", "import_from_statement"].contains(statement.nodeType ?? ""),
                  !isSuppressed(statement, tree: tree) else { return }
            found += unusedBindings(of: statement, tree: tree, uses: uses)
        }
        return found
    }

    /// Lists the bindings of one import statement that nothing outside it uses.
    ///
    /// - Parameters:
    ///   - statement: The import statement.
    ///   - tree: The parsed file.
    ///   - uses: The file's name uses.
    /// - Returns: The unused imports.
    private func unusedBindings(of statement: Node, tree: DeadCodeTree, uses: UseIndex) -> [UnusedDeclaration] {
        bindings(of: statement, tree: tree).filter { !uses.isUsed($0.0, outside: statement.byteRange) }.map {
            tree.unused(.importBinding, $0.0, at: $0.1, detail: "import")
        }
    }

    /// Reports whether an import carries a trailing `# noqa` comment on its last line.
    ///
    /// - Parameters:
    ///   - statement: The import statement.
    ///   - tree: The parsed file.
    /// - Returns: Whether it's suppressed.
    private func isSuppressed(_ statement: Node, tree: DeadCodeTree) -> Bool {
        guard let next = statement.nextSibling, next.nodeType == "comment",
              next.pointRange.lowerBound.row == statement.pointRange.upperBound.row else { return false }
        return tree.text(next)?.contains("noqa") ?? false
    }

    /// Lists the names an import binds: `a` for `import a.b`, the alias for `as`, each name for `from`.
    ///
    /// - Parameters:
    ///   - statement: The import statement.
    ///   - tree: The parsed file.
    /// - Returns: Each bound name and the node it's bound at.
    private func bindings(of statement: Node, tree: DeadCodeTree) -> [(String, Node)] {
        DeadCodeNodes.children(of: statement, field: "name").compactMap { imported in
            if imported.nodeType == "aliased_import" {
                return imported.child(byFieldName: "alias").flatMap { alias in tree.text(alias).map { ($0, alias) } }
            }
            let first = imported.namedChild(at: 0)
            return tree.text(first).map { ($0, imported) }
        }
    }
}
