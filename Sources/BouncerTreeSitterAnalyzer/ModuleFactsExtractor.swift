import Foundation
import SwiftTreeSitter
import BouncerCore

/// Reads a language's imports and exports out of a parse tree, for the project pass.
protocol ModuleFactsExtractor: Sendable {
    /// Extracts module facts from a file's tree.
    ///
    /// - Parameters:
    ///   - root: The parse tree's root.
    ///   - text: Reads a node's source text.
    /// - Returns: The file's imports and exports.
    func facts(root: Node, text: (Node) -> String?) -> ModuleFacts
}

/// Tree traversal helpers shared by the extractors.
enum TreeWalk {
    /// Visits every node in a subtree, parents before children.
    ///
    /// - Parameters:
    ///   - node: The subtree's root.
    ///   - visit: Called once per node.
    static func forEach(_ node: Node, _ visit: (Node) -> Void) {
        visit(node)
        for index in 0..<node.childCount {
            node.child(at: index).map { forEach($0, visit) }
        }
    }

    /// Lists a node's named children.
    ///
    /// - Parameter node: The node.
    /// - Returns: Its named children, in order.
    static func namedChildren(_ node: Node) -> [Node] {
        (0..<node.namedChildCount).compactMap { node.namedChild(at: $0) }
    }

    /// Converts a node's 0-indexed start row to a 1-indexed line.
    ///
    /// - Parameter node: The node.
    /// - Returns: Its first line.
    static func line(_ node: Node) -> Int {
        Int(node.pointRange.lowerBound.row) + 1
    }

    /// Strips a string literal's quotes.
    ///
    /// - Parameter literal: The literal's source text, such as `"./util"`.
    /// - Returns: Its contents.
    static func unquote(_ literal: String) -> String {
        literal.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
    }

    /// Collects a tree's structure facts with one language's collector.
    ///
    /// - Parameters:
    ///   - collector: The language's collector type.
    ///   - root: The parse tree's root.
    ///   - text: Reads a node's source text.
    /// - Returns: The file's types, functions, and `switch` subjects.
    static func structure(
        _ collector: StructureCollector.Type, root: Node, text: (Node) -> String?
    ) -> StructureFacts {
        withoutActuallyEscaping(text) { collector.init(text: $0).collect(root) }
    }
}

/// Python: `import a.b` and `from .a import b`, as dotted specifiers (relative ones keep their dots).
struct PythonModuleFacts: ModuleFactsExtractor {
    /// Extracts Python imports.
    ///
    /// - Parameters:
    ///   - root: The parse tree's root.
    ///   - text: Reads a node's source text.
    /// - Returns: The file's imports; Python has no explicit exports.
    func facts(root: Node, text: (Node) -> String?) -> ModuleFacts {
        var imports: [ImportFact] = []
        TreeWalk.forEach(root) { node in
            for specifier in specifiers(of: node, text: text) {
                imports.append(ImportFact(specifier: specifier, line: TreeWalk.line(node)))
            }
        }
        let structure = TreeWalk.structure(PythonStructure.self, root: root, text: text)
        return ModuleFacts(imports: imports, structure: structure)
    }

    /// Lists the modules one import statement names.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - text: Reads a node's source text.
    /// - Returns: The dotted module names, or none if this isn't an import.
    private func specifiers(of node: Node, text: (Node) -> String?) -> [String] {
        if node.nodeType == "import_from_statement" {
            return node.child(byFieldName: "module_name").flatMap(text).map { [$0] } ?? []
        }
        guard node.nodeType == "import_statement" else { return [] }
        return TreeWalk.namedChildren(node).compactMap { child in
            text(child.nodeType == "aliased_import" ? child.child(byFieldName: "name") ?? child : child)
        }
    }
}

/// Go: each `import "path"`.
struct GoModuleFacts: ModuleFactsExtractor {
    /// Extracts Go imports.
    ///
    /// - Parameters:
    ///   - root: The parse tree's root.
    ///   - text: Reads a node's source text.
    /// - Returns: The file's imports; Go's exports are capitalization, not declarations.
    func facts(root: Node, text: (Node) -> String?) -> ModuleFacts {
        var imports: [ImportFact] = []
        TreeWalk.forEach(root) { node in
            guard node.nodeType == "import_spec",
                  let path = node.child(byFieldName: "path").flatMap(text) else { return }
            imports.append(ImportFact(specifier: TreeWalk.unquote(path), line: TreeWalk.line(node)))
        }
        return ModuleFacts(imports: imports, structure: TreeWalk.structure(GoStructure.self, root: root, text: text))
    }
}
