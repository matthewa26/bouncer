import SwiftTreeSitter
import BouncerCore
import BouncerRules

/// Rust's declaration conventions: `impl` blocks that add methods to a type declared beside them, `pub`
/// visibility modifiers, and doc comments that sit above a declaration's attributes.
extension TreeSitterSummaryBuilder {
    /// Records the members an `impl`-style block adds to the type it names.
    ///
    /// - Parameters:
    ///   - node: The block, such as `impl Widget { … }` or `impl fmt::Display for Widget { … }`.
    ///   - typeField: The field naming the extended type.
    func collectExtension(_ node: Node, typeField: String) {
        guard let target = node.child(byFieldName: typeField), let name = extendedTypeName(target),
              let body = typeBody(of: node) else { return }
        extensionMembers[name, default: 0] += memberCount(of: body)
    }

    /// Names the type an `impl` block extends, without its path or generic arguments.
    ///
    /// - Parameter type: The block's type node, such as `Widget<T>` or `ui::Widget`.
    /// - Returns: The bare type name, such as `Widget`.
    private func extendedTypeName(_ type: Node) -> String? {
        switch type.nodeType {
        case "generic_type": return type.child(byFieldName: "type").flatMap(extendedTypeName)
        case "scoped_type_identifier": return type.child(byFieldName: "name").flatMap(text)
        default: return text(of: type)
        }
    }

    /// Adds the members the file's `impl` blocks give a type to its own count.
    ///
    /// - Parameter type: A collected type.
    /// - Returns: The type with its extension members counted, or unchanged when nothing extends it.
    func withExtensionMembers(_ type: CollectedType) -> CollectedType {
        guard let extra = extensionMembers[type.name] else { return type }
        return CollectedType(
            name: type.name, memberCount: type.memberCount + extra, startLine: type.startLine, endLine: type.endLine,
            cohesionGroups: type.cohesionGroups, shape: type.shape, structure: type.structure, design: type.design
        )
    }

    /// Applies Rust visibility: bare `pub` is public, `pub(crate)`, `pub(super)`, and `pub(in …)` are internal,
    /// and no modifier is private. A trait's methods take the trait's own visibility.
    ///
    /// - Parameter node: The function node.
    /// - Returns: Its visibility.
    func visibilityByModifier(_ node: Node) -> DeclarationVisibility {
        let trait = node.parent?.parent.flatMap { $0.nodeType == "trait_item" ? $0 : nil }
        let modifier = TreeWalk.namedChildren(trait ?? node).first { $0.nodeType == "visibility_modifier" }
        guard let written = modifier.flatMap(text) else { return .private }
        return written == "pub" ? .public : .internal
    }

    /// Checks for a Rust doc: a `///` or `/** */` comment or a `#[doc = …]` attribute among the comments and
    /// attributes directly above a declaration, or a `//!` or `/*! */` comment opening its body.
    ///
    /// - Parameter node: The declaration node.
    /// - Returns: Whether it's documented.
    func hasRustDoc(_ node: Node) -> Bool {
        let preamble = RustSyntax.preamble(of: node).compactMap(text)
        if preamble.contains(where: RustSyntax.isOuterDoc) { return true }
        let first = node.child(byFieldName: "body")?.namedChild(at: 0).flatMap(text) ?? ""
        return first.hasPrefix("//!") || first.hasPrefix("/*!")
    }
}

/// Rust syntax helpers shared by the summary builder and the Rust smell checks.
enum RustSyntax {
    /// The nodes that may sit between a declaration and its doc comment.
    static let preambleNodeTypes: Set<String> = ["attribute_item", "line_comment", "block_comment"]

    /// Lists the comments and attributes directly above a node, nearest first, stopping at a blank line.
    ///
    /// - Parameter node: The declaration or statement.
    /// - Returns: Its preamble.
    static func preamble(of node: Node) -> [Node] {
        var items: [Node] = [], current = node
        while let previous = current.previousNamedSibling, preambleNodeTypes.contains(previous.nodeType ?? ""),
              lastRow(of: previous) + 1 >= current.pointRange.lowerBound.row {
            items.append(previous)
            current = previous
        }
        return items
    }

    /// Finds the last row a node's text is on; a line comment's range ends at the start of the next line.
    ///
    /// - Parameter node: The node.
    /// - Returns: Its last row, 0-indexed.
    static func lastRow(of node: Node) -> UInt32 {
        let range = node.pointRange
        return range.upperBound.column == 0 && range.upperBound.row > range.lowerBound.row
            ? range.upperBound.row - 1 : range.upperBound.row
    }

    /// Reports whether a node is a line or block comment.
    ///
    /// - Parameter node: The node.
    /// - Returns: Whether it's a comment.
    static func isComment(_ node: Node) -> Bool {
        node.nodeType == "line_comment" || node.nodeType == "block_comment"
    }

    /// Reports whether a comment or attribute documents the item below it: `///`, `/** */`, or `#[doc = …]`.
    ///
    /// - Parameter text: The comment's or attribute's source text.
    /// - Returns: Whether it's an outer doc.
    static func isOuterDoc(_ text: String) -> Bool {
        if text.hasPrefix("#[doc") { return true }
        if text.hasPrefix("///") { return !text.hasPrefix("////") }
        return text.hasPrefix("/**") && !text.hasPrefix("/***") && text != "/**/"
    }
}
