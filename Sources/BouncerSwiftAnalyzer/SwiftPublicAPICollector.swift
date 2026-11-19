import SwiftSyntax
import BouncerCore

/// Collects a Swift file's `public`/`open` declarations, for the `unused-public-symbol` rule.
///
/// Members of a `public extension` count as public unless marked otherwise. Overrides, operators, `@objc`
/// declarations, protocol requirements, and `@main` types are skipped: something outside the code calls them.
final class SwiftPublicAPICollector: SyntaxVisitor {
    private(set) var exports: [ExportFact] = []
    private let converter: SourceLocationConverter
    private var publicExtensionDepth = 0

    /// Creates a collector for a parsed file.
    ///
    /// - Parameter converter: Converts syntax positions to line numbers.
    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    /// Records a public function.
    ///
    /// - Parameter node: The function.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node, modifiers: node.modifiers, attributes: node.attributes)
        return .skipChildren
    }

    /// Records each name a public `let`/`var` declares.
    ///
    /// - Parameter node: The variable declaration.
    /// - Returns: `.skipChildren`.
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
            record(name, node, modifiers: node.modifiers, attributes: node.attributes)
        }
        return .skipChildren
    }

    /// Records a public class, then its members.
    ///
    /// - Parameter node: The class.
    /// - Returns: `.visitChildren`, unless it's a `@main` type.
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        recordType(node.name.text, node, modifiers: node.modifiers, attributes: node.attributes)
    }

    /// Records a public struct, then its members.
    ///
    /// - Parameter node: The struct.
    /// - Returns: `.visitChildren`, unless it's a `@main` type.
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordType(node.name.text, node, modifiers: node.modifiers, attributes: node.attributes)
    }

    /// Records a public enum, then its members.
    ///
    /// - Parameter node: The enum.
    /// - Returns: `.visitChildren`, unless it's a `@main` type.
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        recordType(node.name.text, node, modifiers: node.modifiers, attributes: node.attributes)
    }

    /// Records a public protocol, skipping its requirements, which conforming types satisfy.
    ///
    /// - Parameter node: The protocol.
    /// - Returns: `.skipChildren`.
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node, modifiers: node.modifiers, attributes: node.attributes)
        return .skipChildren
    }

    /// Records a public type alias.
    ///
    /// - Parameter node: The type alias.
    /// - Returns: `.skipChildren`.
    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node, modifiers: node.modifiers, attributes: node.attributes)
        return .skipChildren
    }

    /// Enters an extension, making its members public by default if it's a `public extension`.
    ///
    /// - Parameter node: The extension.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if Self.isPublic(node.modifiers) { publicExtensionDepth += 1 }
        return .visitChildren
    }

    /// Leaves an extension.
    ///
    /// - Parameter node: The extension.
    override func visitPost(_ node: ExtensionDeclSyntax) {
        if Self.isPublic(node.modifiers) { publicExtensionDepth -= 1 }
    }

    /// Records a type if public, and decides whether to look inside it.
    ///
    /// - Parameters:
    ///   - name: The type's name.
    ///   - node: The declaration, for its line.
    ///   - modifiers: Its modifiers.
    ///   - attributes: Its attributes.
    /// - Returns: `.skipChildren` for a `@main` type, whose members the runtime calls, else `.visitChildren`.
    private func recordType(
        _ name: String, _ node: some SyntaxProtocol, modifiers: DeclModifierListSyntax, attributes: AttributeListSyntax
    ) -> SyntaxVisitorContinueKind {
        guard !Self.has("main", in: attributes) else { return .skipChildren }
        record(name, node, modifiers: modifiers, attributes: attributes)
        return .visitChildren
    }

    /// Records a declaration if it's public and not called from outside the code.
    ///
    /// - Parameters:
    ///   - name: The declared name.
    ///   - node: The declaration, for its line.
    ///   - modifiers: Its modifiers.
    ///   - attributes: Its attributes.
    private func record(
        _ name: String, _ node: some SyntaxProtocol, modifiers: DeclModifierListSyntax, attributes: AttributeListSyntax
    ) {
        let isPublic = Self.isPublic(modifiers) || (publicExtensionDepth > 0 && !Self.isRestricted(modifiers))
        let isExempt = modifiers.contains { $0.name.tokenKind == .keyword(.override) }
            || Self.has("objc", in: attributes) || !(name.first.map { $0.isLetter || $0 == "_" } ?? false)
        guard isPublic, !isExempt else { return }
        let line = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        exports.append(ExportFact(name: name, line: line))
    }

    /// Reports whether modifiers include `public` or `open`.
    ///
    /// - Parameter modifiers: The modifiers.
    /// - Returns: Whether the declaration is public.
    private static func isPublic(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { [.keyword(.public), .keyword(.open)].contains($0.name.tokenKind) }
    }

    /// Reports whether modifiers narrow access below public.
    ///
    /// - Parameter modifiers: The modifiers.
    /// - Returns: Whether the declaration is `internal`, `fileprivate`, or `private`.
    private static func isRestricted(_ modifiers: DeclModifierListSyntax) -> Bool {
        let restricted: [TokenKind] = [.keyword(.internal), .keyword(.fileprivate), .keyword(.private)]
        return modifiers.contains { restricted.contains($0.name.tokenKind) }
    }

    /// Reports whether attributes include one by name, such as `main` for `@main`.
    ///
    /// - Parameters:
    ///   - name: The attribute's name, without `@`.
    ///   - attributes: The attributes.
    /// - Returns: Whether it's present.
    private static func has(_ name: String, in attributes: AttributeListSyntax) -> Bool {
        attributes.contains { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == name }
    }
}

/// Collects every name a Swift file refers to: references to declarations, member names, and type names.
final class SwiftReferenceCollector: SyntaxVisitor {
    private(set) var names: Set<String> = []

    /// Records a referenced name, including the member in `a.member`.
    ///
    /// - Parameter node: The reference.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.baseName.text)
        return .visitChildren
    }

    /// Records a type name, such as `Foo` in `let x: Foo`.
    ///
    /// - Parameter node: The type.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.name.text)
        return .visitChildren
    }

    /// Records a nested type name, such as `Bar` in `Foo.Bar`.
    ///
    /// - Parameter node: The member type.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.name.text)
        return .visitChildren
    }
}
