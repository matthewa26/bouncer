import SwiftTreeSitter
import BouncerCore

/// TypeScript and JavaScript: `import`/`export … from`, `require`, dynamic `import()`, and every export.
struct JavaScriptModuleFacts: ModuleFactsExtractor {
    /// Extracts imports and exports.
    ///
    /// - Parameters:
    ///   - root: The parse tree's root.
    ///   - text: Reads a node's source text.
    /// - Returns: The file's imports and exports.
    func facts(root: Node, text: (Node) -> String?) -> ModuleFacts {
        var imports: [ImportFact] = [], exports: [ExportFact] = []
        TreeWalk.forEach(root) { node in
            if let fact = importFact(node, text: text) { imports.append(fact) }
            if node.nodeType == "export_statement" { exports += exportFacts(node, text: text) }
        }
        let structure = TreeWalk.structure(JavaScriptStructure.self, root: root, text: text)
        return ModuleFacts(imports: imports, exports: exports, structure: structure)
    }

    /// Reads an import, re-export, `require`, or dynamic `import()`.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - text: Reads a node's source text.
    /// - Returns: The import, or `nil` if the node isn't one.
    private func importFact(_ node: Node, text: (Node) -> String?) -> ImportFact? {
        switch node.nodeType {
        case "import_statement", "export_statement":
            return statementImport(node, text: text)
        case "call_expression":
            return loadingCall(node, text: text)
        default:
            return nil
        }
    }

    /// Reads an `import … from` or `export … from` statement's source and imported names.
    ///
    /// - Parameters:
    ///   - node: An import or export statement.
    ///   - text: Reads a node's source text.
    /// - Returns: The import, or `nil` for an export with no `from` source.
    private func statementImport(_ node: Node, text: (Node) -> String?) -> ImportFact? {
        guard let source = node.child(byFieldName: "source").flatMap(text) else { return nil }
        let names = importedNames(node, text: text)
        return ImportFact(specifier: TreeWalk.unquote(source), line: TreeWalk.line(node), names: names)
    }

    /// Reads `require("x")` or `import("x")` as a namespace import.
    ///
    /// - Parameters:
    ///   - node: A call expression.
    ///   - text: Reads a node's source text.
    /// - Returns: The import, or `nil` for any other call.
    private func loadingCall(_ node: Node, text: (Node) -> String?) -> ImportFact? {
        guard let callee = node.child(byFieldName: "function"), ["require", "import"].contains(text(callee) ?? ""),
              let argument = node.child(byFieldName: "arguments").flatMap({ TreeWalk.namedChildren($0).first }),
              argument.nodeType == "string", let source = text(argument) else { return nil }
        return ImportFact(specifier: TreeWalk.unquote(source), line: TreeWalk.line(node))
    }

    /// Lists the names an import or re-export pulls in.
    ///
    /// - Parameters:
    ///   - node: The import or `export … from` statement.
    ///   - text: Reads a node's source text.
    /// - Returns: Imported names: `default`, `*`, or each named specifier's original name; empty for a
    ///   side-effect import.
    private func importedNames(_ node: Node, text: (Node) -> String?) -> [String] {
        var names: [String] = []
        TreeWalk.forEach(node) { child in
            if let name = importedName(child, in: node, text: text) { names.append(name) }
        }
        return names
    }

    /// Reads the name one node inside an import or re-export pulls in, if it names one.
    ///
    /// - Parameters:
    ///   - child: A node inside the statement.
    ///   - statement: The import or `export … from` statement.
    ///   - text: Reads a node's source text.
    /// - Returns: `default`, `*`, or the specifier's original name, or `nil` if the node names nothing.
    private func importedName(_ child: Node, in statement: Node, text: (Node) -> String?) -> String? {
        switch child.nodeType {
        case "namespace_import", "namespace_export": return "*"
        case "import_specifier", "export_specifier": return child.child(byFieldName: "name").flatMap(text)
        case "identifier" where child.parent?.nodeType == "import_clause": return "default"
        case "*" where statement.nodeType == "export_statement": return "*"
        default: return nil
        }
    }

    /// Lists the names an `export` statement exports.
    ///
    /// - Parameters:
    ///   - node: The export statement.
    ///   - text: Reads a node's source text.
    /// - Returns: Each exported name and its line.
    private func exportFacts(_ node: Node, text: (Node) -> String?) -> [ExportFact] {
        let line = TreeWalk.line(node)
        if (0..<node.childCount).contains(where: { node.child(at: $0)?.nodeType == "default" }) {
            return [ExportFact(name: "default", line: line)]
        }
        if let declaration = node.child(byFieldName: "declaration") {
            return declaredNames(declaration, text: text).map { ExportFact(name: $0, line: line) }
        }
        return exportedClauseNames(node, text: text).map { ExportFact(name: $0, line: line) }
    }

    /// Lists the names a declaration introduces, including each `const a = …, b = …` declarator.
    ///
    /// - Parameters:
    ///   - declaration: The exported declaration.
    ///   - text: Reads a node's source text.
    /// - Returns: The declared names.
    private func declaredNames(_ declaration: Node, text: (Node) -> String?) -> [String] {
        if let name = declaration.child(byFieldName: "name").flatMap(text) { return [name] }
        return TreeWalk.namedChildren(declaration).filter { $0.nodeType == "variable_declarator" }
            .compactMap { $0.child(byFieldName: "name").flatMap(text) }
    }

    /// Lists the names an `export { a, b as c }` clause exports, by their exported (aliased) names.
    ///
    /// - Parameters:
    ///   - node: The export statement.
    ///   - text: Reads a node's source text.
    /// - Returns: The exported names.
    private func exportedClauseNames(_ node: Node, text: (Node) -> String?) -> [String] {
        var names: [String] = []
        TreeWalk.forEach(node) { child in
            guard child.nodeType == "export_specifier" else { return }
            let nameNode = child.child(byFieldName: "alias") ?? child.child(byFieldName: "name")
            nameNode.flatMap(text).map { names.append($0) }
        }
        return names
    }
}
