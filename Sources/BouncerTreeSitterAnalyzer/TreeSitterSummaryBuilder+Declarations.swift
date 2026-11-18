import SwiftTreeSitter
import BouncerCore
import BouncerRules

/// Naming, wrapper, and visibility conventions for languages whose functions are often
/// anonymous expressions bound to a name, such as TypeScript's `export const f = () => {}`.
extension TreeSitterSummaryBuilder {
    /// Resolves a function's name from its own `name` field, or from the node that binds it.
    ///
    /// A member binding such as `module.exports.load = function () {}` resolves to its last
    /// component, `load`.
    ///
    /// - Parameter node: The function node.
    /// - Returns: The name, or `CollectedFunction.anonymousName` for an unbound expression.
    func functionName(of node: Node) -> String {
        if let name = node.child(byFieldName: "name").flatMap(text) { return name }
        let anonymous = CollectedFunction.anonymousName
        guard let parent = node.parent, let parentType = parent.nodeType,
              let field = spec.nameSourceParents[parentType] else { return anonymous }
        guard let binding = parent.child(byFieldName: field).flatMap(text) else { return anonymous }
        return binding.split(separator: ".").last.map(String.init) ?? binding
    }

    /// Walks outward through declaration wrappers, such as `const` and `export`, to the outermost one.
    ///
    /// - Parameter node: The declaration node.
    /// - Returns: The node a doc comment would sit directly above.
    func declarationAnchor(of node: Node) -> Node {
        var anchor = node
        while let parent = anchor.parent, let type = parent.nodeType, spec.declarationWrapperNodeTypes.contains(type) {
            anchor = parent
        }
        return anchor
    }

    /// Applies TypeScript/JavaScript visibility: `export` or a public class member is public.
    ///
    /// - Parameters:
    ///   - node: The function node.
    ///   - name: The resolved function name.
    /// - Returns: `.private` for anonymous, `private`, or `#name` members; `.internal` for
    ///   `protected` members and unexported top-level functions; otherwise `.public`.
    func visibilityByExport(_ node: Node, name: String) -> DeclarationVisibility {
        if name == CollectedFunction.anonymousName || name.hasPrefix("#") { return .private }
        if let modifier = accessibilityModifier(of: node) { return modifier == "private" ? .private : .internal }
        if node.nodeType == "method_definition" || node.parent?.nodeType == "public_field_definition" { return .public }
        return declarationAnchor(of: node).nodeType == "export_statement" ? .public : .internal
    }

    /// Finds a non-public TypeScript accessibility modifier on a member or the field that holds it.
    ///
    /// - Parameter node: The function node.
    /// - Returns: `"private"` or `"protected"`, or `nil` if the member is public.
    private func accessibilityModifier(of node: Node) -> String? {
        let owner = node.parent?.nodeType == "public_field_definition" ? node.parent : node
        guard let owner else { return nil }
        for index in 0..<owner.namedChildCount {
            guard let child = owner.namedChild(at: index), child.nodeType == "accessibility_modifier" else { continue }
            let modifier = text(of: child)
            if modifier == "private" || modifier == "protected" { return modifier }
        }
        return nil
    }
}
