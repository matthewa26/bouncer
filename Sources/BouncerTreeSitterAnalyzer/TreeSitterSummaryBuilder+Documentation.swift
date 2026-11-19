import SwiftTreeSitter
import BouncerRules

/// The doc-completeness facts for TS/JS JSDoc and Python docstrings: the doc's text, the parameter names,
/// and whether the function returns a value or throws.
extension TreeSitterSummaryBuilder {
    /// Gathers a function's doc comment and signature facts.
    ///
    /// - Parameters:
    ///   - node: The function node.
    ///   - body: Its body.
    /// - Returns: The facts, or `nil` without a doc comment or a doc convention to check.
    func documentationFacts(of node: Node, body: Node) -> DocumentationFacts? {
        guard let collector = quality, let docs = collector.quality.flow?.documentation,
              let doc = docText(of: node, body: body, style: docs.style) else { return nil }
        let entries = collector.parameterNodes(of: node)
        let parameters = entries.compactMap { signatureParameter($0, docs: docs, collector: collector) }
        let unnamed = parameters.count < entries.count || parameters.contains(where: \.isVariadic)
        return DocumentationFacts(
            style: docs.style, text: doc, parameters: parameters, hasUnnamedParameters: unnamed,
            returnsValue: returnsValue(node, body: body, docs: docs), throwsError: throwsError(in: body, docs: docs)
        )
    }

    /// Reads a function's doc: the `/** */` comment above it, or the docstring opening its body.
    ///
    /// - Parameters:
    ///   - node: The function node.
    ///   - body: Its body.
    ///   - style: The language's doc convention.
    /// - Returns: The doc's raw text, or `nil` if it has none.
    private func docText(of node: Node, body: Node, style: DocStyle) -> String? {
        guard style == .jsdoc else {
            guard hasDocstring(node), let statement = body.namedChild(at: 0) else { return nil }
            return statement.namedChild(at: 0).flatMap(text)
        }
        let anchor = declarationAnchor(of: node)
        guard hasPrecedingComment(anchor, prefix: "/**") else { return nil }
        return anchor.previousNamedSibling.flatMap(text)
    }

    /// Reads one parameter-list entry's name.
    ///
    /// - Parameters:
    ///   - entry: The entry.
    ///   - docs: The language's doc node types.
    ///   - collector: The language's quality collector.
    /// - Returns: The parameter, or `nil` for an entry with no single plain name, such as `{ a, b }` or `this`.
    private func signatureParameter(
        _ entry: Node, docs: DocumentationSpec, collector: TreeSitterQualityCollector
    ) -> SignatureParameter? {
        let type = entry.nodeType ?? ""
        let isVariadic = docs.variadicParameters.contains(type)
        guard let field = isVariadic ? "*" : docs.namedParameters[type] else { return nil }
        let identifiers = collector.namedChildren(of: entry).filter { $0.nodeType == "identifier" }
        let nameNode = field.isEmpty ? entry : field == "*" ? identifiers.first : entry.child(byFieldName: field)
        guard let nameNode, nameNode.nodeType == "identifier", let name = text(of: nameNode), name != "this" else {
            return nil
        }
        return SignatureParameter(name: name, isVariadic: isVariadic)
    }

    /// Reports whether a function returns a value: by its return type annotation, an expression body, or a
    /// `return`/`yield` with a value in its own body. A Python property's value isn't a `Returns:` entry.
    ///
    /// - Parameters:
    ///   - node: The function node.
    ///   - body: Its body.
    ///   - docs: The language's doc node types.
    /// - Returns: Whether it returns a value.
    private func returnsValue(_ node: Node, body: Node, docs: DocumentationSpec) -> Bool {
        guard !isProperty(node, docs: docs) else { return false }
        if let annotation = node.child(byFieldName: "return_type").flatMap(text) {
            let type = annotation.drop { $0 == ":" || $0 == " " || $0 == "-" || $0 == ">" }
            return !docs.voidReturnTypes.contains(String(type))
        }
        guard body.nodeType == "statement_block" || body.nodeType == "block" else { return true }
        return ownNodes(in: body).contains { node in
            node.nodeType == "yield" || (node.nodeType == "return_statement" && returnsSomething(node))
        }
    }

    /// Reports whether a `return` hands back a value other than `None`/`undefined`.
    ///
    /// - Parameter node: The return statement.
    /// - Returns: Whether it returns something.
    private func returnsSomething(_ node: Node) -> Bool {
        guard let value = node.namedChild(at: 0), value.nodeType != "comment" else { return false }
        return !["none", "undefined"].contains(value.nodeType ?? "")
    }

    /// Reports whether a Python method is decorated as a property.
    ///
    /// - Parameters:
    ///   - node: The function node.
    ///   - docs: The language's doc node types.
    /// - Returns: Whether a property decorator wraps it.
    private func isProperty(_ node: Node, docs: DocumentationSpec) -> Bool {
        guard let wrapper = node.parent, wrapper.nodeType == "decorated_definition" else { return false }
        let decorators = (0..<wrapper.namedChildCount).compactMap { wrapper.namedChild(at: $0) }
            .filter { $0.nodeType == "decorator" }.compactMap(text)
        return decorators.contains { decorator in docs.propertyDecorators.contains { decorator.hasSuffix($0) } }
    }

    /// Reports whether a function throws from its own body: a `throw`/`raise` outside any `try` block, other
    /// than a bare re-`raise` or a `NotImplementedError` stub.
    ///
    /// - Parameters:
    ///   - body: The function's body.
    ///   - docs: The language's doc node types.
    /// - Returns: Whether it throws.
    private func throwsError(in body: Node, docs: DocumentationSpec) -> Bool {
        ownNodes(in: body).contains { node in
            guard node.nodeType == docs.throwNodeType, let value = node.namedChild(at: 0) else { return false }
            return !(text(of: value) ?? "").hasPrefix("NotImplementedError")
        }
    }

    /// Lists a body's nodes outside nested functions, classes, and `try` blocks.
    ///
    /// - Parameter node: The body or a node inside it.
    /// - Returns: Every node it holds, in walk order.
    private func ownNodes(in node: Node) -> [Node] {
        let children: [Node] = (0..<node.namedChildCount).compactMap { node.namedChild(at: $0) }
        return children.filter { isOwn($0, parent: node) }.flatMap { [$0] + ownNodes(in: $0) }
    }

    /// Reports whether a child still belongs to the function's own flow: not a nested function or class, and
    /// not the guarded block of a `try`.
    ///
    /// - Parameters:
    ///   - child: The child node.
    ///   - parent: Its parent.
    /// - Returns: Whether to include it and walk into it.
    private func isOwn(_ child: Node, parent: Node) -> Bool {
        let type = child.nodeType ?? ""
        let closures = quality?.quality.complexity.closureNodeTypes ?? []
        guard !spec.functionNodeTypes.contains(type), !spec.classNodeTypes.contains(type), !closures.contains(type)
        else { return false }
        return parent.nodeType != "try_statement" || ["catch_clause", "except_clause", "finally_clause"].contains(type)
    }
}
