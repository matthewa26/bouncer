import SwiftTreeSitter

/// The names a Python file's top-level imports bind, so `law-of-demeter` can tell a module path such as
/// `pip._internal.utils.misc.ensure_dir()` from a chain of objects.
extension TreeSitterSummaryBuilder {
    /// Collects the names bound by a Python file's top-level `import` and `from … import` statements.
    ///
    /// - Parameter root: The parse tree's root.
    /// - Returns: The bound names; empty for any other language.
    func importedNames(in root: Node) -> Set<String> {
        guard spec.coreLanguage == .python else { return [] }
        let imports = (0..<root.namedChildCount).compactMap { root.namedChild(at: $0) }
            .filter { spec.importNodeTypes.contains($0.nodeType ?? "") }
        return Set(imports.flatMap(boundNames))
    }

    /// Reads the names one import statement binds: the first part of `import a.b`, an `as` alias, or each
    /// name a `from` import brings in (but not the module it comes from).
    ///
    /// - Parameter statement: The import statement.
    /// - Returns: The bound names.
    private func boundNames(_ statement: Node) -> [String] {
        (0..<statement.childCount).compactMap { index -> String? in
            guard statement.fieldNameForChild(at: index) != "module_name", let child = statement.child(at: index)
            else { return nil }
            if child.nodeType == "aliased_import" { return child.child(byFieldName: "alias").flatMap(text) }
            guard child.nodeType == "dotted_name" else { return nil }
            return child.namedChild(at: 0).flatMap(text)
        }
    }
}
