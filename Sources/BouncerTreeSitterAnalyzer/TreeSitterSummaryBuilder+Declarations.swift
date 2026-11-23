import SwiftTreeSitter
import BouncerCore
import BouncerRules

/// Naming, wrapper, visibility, and documentation conventions: functions that are anonymous expressions
/// bound to a name, such as TypeScript's `export const f = () => {}`, and C-family declarations that keep
/// their names, bodies, and members outside of fields, such as Objective-C methods and classes.
extension TreeSitterSummaryBuilder {
    /// Resolves a function's name from its own `name` field, or from the node that binds it.
    ///
    /// A member binding such as `module.exports.load = function () {}` resolves to its last
    /// component, `load`.
    ///
    /// - Parameter node: The function node.
    /// - Returns: The name, or `CollectedFunction.anonymousName` for an unbound expression.
    func functionName(of node: Node) -> String {
        if let name = node.child(byFieldName: "name").flatMap(text) ?? spec.cDeclarations?.name(of: node, text: text) {
            return name
        }
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

    /// Checks for a `///` or `/** */` comment directly above a declaration or its wrapper.
    ///
    /// - Parameter node: The declaration node.
    /// - Returns: Whether such a comment documents it.
    func hasCDocComment(_ node: Node) -> Bool {
        let anchor = declarationAnchor(of: node)
        return hasPrecedingComment(anchor, prefix: "///") || hasPrecedingComment(anchor, prefix: "/**")
    }

    /// Reads a function's body: its `body` field, or for a C-family grammar its body block child.
    ///
    /// - Parameter node: The function node.
    /// - Returns: The body, or `nil` for a declaration without one.
    func functionBody(of node: Node) -> Node? {
        node.child(byFieldName: "body") ?? spec.cDeclarations?.body(of: node)
    }

    /// Reads a type's body: its `body` field, or for a C-family grammar the type node, which holds its members.
    ///
    /// - Parameter node: The type node.
    /// - Returns: The body, or `nil` for a declaration without one.
    func typeBody(of node: Node) -> Node? {
        node.child(byFieldName: "body") ?? (spec.cDeclarations == nil ? nil : node)
    }

    /// Names a type: its `name` field, or for a C-family grammar its identifier and category.
    ///
    /// - Parameter node: The type node.
    /// - Returns: The name, or `"<anonymous>"` without one.
    func typeName(of node: Node) -> String {
        node.child(byFieldName: "name").flatMap(text) ?? spec.cDeclarations?.typeName(of: node, text: text)
            ?? "<anonymous>"
    }

    /// Counts a type's members: its body's named children (less non-members such as Rust's comments), or for a
    /// C-family grammar its declared methods, properties, and instance variables.
    ///
    /// - Parameter body: The type's body (for Objective-C, the type node itself).
    /// - Returns: The member count.
    func memberCount(of body: Node) -> Int {
        spec.cDeclarations.map { $0.members(of: body).count }
            ?? TreeWalk.namedChildren(body).filter { !spec.nonMemberNodeTypes.contains($0.nodeType ?? "") }.count
    }

    /// Applies Objective-C visibility: a `static` C function or an underscored method is private, any other
    /// method is internal (its header declares, and documents, the public contract), and any other C
    /// function is public.
    ///
    /// - Parameters:
    ///   - node: The function or method node.
    ///   - name: The resolved name.
    /// - Returns: The declaration's visibility.
    func visibilityByFileScope(_ node: Node, name: String) -> DeclarationVisibility {
        guard let declarations = spec.cDeclarations else { return .public }
        if name.hasPrefix("_") || declarations.isFileScoped(node, text: text) { return .private }
        return declarations.selectorMethodNodeTypes.contains(node.nodeType ?? "") ? .internal : .public
    }

    /// Determines a declaration's access level, per this language's convention.
    ///
    /// - Parameters:
    ///   - node: The declaration node, for conventions that read modifiers or wrappers.
    ///   - name: The declared identifier.
    /// - Returns: The declaration's inferred visibility.
    func visibility(of node: Node, name: String) -> DeclarationVisibility {
        switch spec.visibilityConvention {
        case .leadingUnderscore: visibilityByLeadingUnderscore(name)
        case .leadingCase: (name.first?.isUppercase ?? false) ? .public : .internal
        case .exportKeyword: visibilityByExport(node, name: name)
        case .fileScope: visibilityByFileScope(node, name: name)
        case .visibilityModifier: visibilityByModifier(node)
        case .accessModifier: visibilityByAccessModifier(node)
        }
    }

    /// Applies Python's underscore-prefix naming convention.
    ///
    /// - Parameter name: The declared identifier.
    /// - Returns: `.private` for a double leading underscore, `.internal` for one, else `.public`.
    func visibilityByLeadingUnderscore(_ name: String) -> DeclarationVisibility {
        if name.hasPrefix("__") && !name.hasSuffix("__") { return .private }
        if name.hasPrefix("_") { return .internal }
        return .public
    }

    /// Checks whether a declaration is documented, per this language's convention.
    ///
    /// - Parameter node: The function/method declaration node.
    /// - Returns: Whether it counts as documented.
    func isDocumented(_ node: Node) -> Bool {
        switch spec.documentationStyle {
        case .docstring: hasDocstring(node)
        case .precedingComment: hasPrecedingComment(node)
        case .jsdoc: hasPrecedingComment(declarationAnchor(of: node), prefix: "/**")
        case .cDocComment: hasCDocComment(node)
        case .rustDoc: hasRustDoc(node)
        }
    }
}
