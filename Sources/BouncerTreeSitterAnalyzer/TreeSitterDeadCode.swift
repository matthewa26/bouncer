import Foundation
import SwiftTreeSitter
import BouncerCore
import BouncerRules

/// Finds one language's private symbols, imports, and parameters nothing in the file uses.
///
/// Go has none: a Go package spans files, so an unexported name unused in one file may be used in
/// another, and the compiler already rejects unused imports.
protocol DeadCodeExtractor: Sendable {
    /// Lists a file's unused declarations.
    ///
    /// - Parameter tree: The parsed file.
    /// - Returns: Its unused declarations, in source order per kind.
    func unusedDeclarations(in tree: DeadCodeTree) -> [UnusedDeclaration]
}

/// A parsed file, as the dead-code extractors read it.
struct DeadCodeTree {
    let root: Node
    let fileName: String
    private let source: String

    /// Wraps a file's parse tree.
    ///
    /// - Parameters:
    ///   - root: The parse tree's root.
    ///   - file: The file, for its name and node text.
    init(root: Node, file: SourceFile) {
        self.root = root
        self.fileName = file.path.lastPathComponent
        self.source = file.contents
    }

    /// Reads a node's source text.
    ///
    /// - Parameter node: The node.
    /// - Returns: Its text, or `nil` if its range doesn't map onto the source.
    func text(_ node: Node?) -> String? {
        guard let node, let range = Range(node.range, in: source) else { return nil }
        return String(source[range])
    }

    /// Reads one field of a node as text.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - field: The field name, such as `"name"`.
    /// - Returns: The field's text, or `nil` if the node has no such field.
    func text(_ node: Node, field: String) -> String? {
        text(node.child(byFieldName: field))
    }

    /// Builds a declaration for a node, at its first line.
    ///
    /// - Parameters:
    ///   - kind: Which dead-code rule reports it.
    ///   - name: The declared name.
    ///   - node: The node it's declared at.
    ///   - detail: What it is, or for a parameter, its function's name.
    /// - Returns: The unused declaration.
    func unused(_ kind: DeadCodeKind, _ name: String, at node: Node, detail: String) -> UnusedDeclaration {
        UnusedDeclaration(kind: kind, name: name, line: TreeWalk.line(node), detail: detail)
    }
}

/// Where each name is used in a file, by byte offset, so a declaration's own name doesn't count.
struct UseIndex {
    private var offsets: [String: [UInt32]] = [:]

    /// Indexes every use in a tree.
    ///
    /// - Parameters:
    ///   - tree: The parsed file.
    ///   - types: The node types whose text is a use of that name, such as `identifier`.
    ///   - extra: Further names a node uses without naming them as identifiers, such as a string
    ///     in `__all__`.
    init(_ tree: DeadCodeTree, types: Set<String>, extra: (Node) -> [String]) {
        TreeWalk.forEach(tree.root) { node in
            let offset = node.byteRange.lowerBound
            if let type = node.nodeType, types.contains(type), let name = tree.text(node) {
                offsets[name, default: []].append(offset)
            }
            for name in extra(node) { offsets[name, default: []].append(offset) }
        }
    }

    /// Reports whether a name is used anywhere in the file.
    ///
    /// - Parameter name: The name.
    /// - Returns: Whether it's used at all.
    func contains(_ name: String) -> Bool {
        offsets[name] != nil
    }

    /// Reports whether a name is used anywhere outside a declaration's own extent.
    ///
    /// - Parameters:
    ///   - name: The declared name.
    ///   - extent: The declaration's byte range.
    /// - Returns: Whether any use falls outside it.
    func isUsed(_ name: String, outside extent: Range<UInt32>) -> Bool {
        (offsets[name] ?? []).contains { !extent.contains($0) }
    }

    /// Reports whether a name is used inside a range, other than at its own declaration.
    ///
    /// - Parameters:
    ///   - name: The declared name.
    ///   - extent: The range to look in, such as a function.
    ///   - declaration: The byte offset of the name's own declaration, which doesn't count.
    /// - Returns: Whether any other use falls inside the range.
    func isUsed(_ name: String, within extent: Range<UInt32>, except declaration: UInt32) -> Bool {
        (offsets[name] ?? []).contains { extent.contains($0) && $0 != declaration }
    }
}

/// Small node helpers shared by the dead-code extractors.
enum DeadCodeNodes {
    /// Lists a node's children of one field, such as each `name` of a Python import.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - field: The field name.
    /// - Returns: The matching children, in order.
    static func children(of node: Node, field: String) -> [Node] {
        (0..<node.childCount).compactMap { node.fieldNameForChild(at: $0) == field ? node.child(at: $0) : nil }
    }

    /// Lists every type among a node's children, named or not, such as a TypeScript `readonly` keyword.
    ///
    /// - Parameter node: The node.
    /// - Returns: Its children's node types.
    static func childTypes(of node: Node) -> Set<String> {
        Set((0..<node.childCount).compactMap { node.child(at: $0)?.nodeType })
    }

    /// Finds the closest ancestor matching a condition.
    ///
    /// - Parameters:
    ///   - node: The node to start above.
    ///   - matches: The condition.
    /// - Returns: The ancestor, or `nil` if none matches.
    static func ancestor(of node: Node, where matches: (Node) -> Bool) -> Node? {
        var current = node.parent
        while let candidate = current, !matches(candidate) { current = candidate.parent }
        return current
    }
}
