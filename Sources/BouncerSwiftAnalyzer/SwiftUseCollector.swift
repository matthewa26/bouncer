import SwiftSyntax

/// Records where each name is used: references to declarations, member names, type names, and the
/// shorthand `if let x` binding, which reads `x` without a reference expression.
final class SwiftUseCollector: SyntaxVisitor {
    private(set) var positions: [String: [AbsolutePosition]] = [:]

    /// Creates a use collector.
    init() {
        super.init(viewMode: .sourceAccurate)
    }

    /// Lists every name used anywhere inside a subtree, such as a function body.
    ///
    /// - Parameter node: The subtree.
    /// - Returns: The names it uses.
    static func names(in node: some SyntaxProtocol) -> Set<String> {
        let collector = SwiftUseCollector()
        collector.walk(node)
        return Set(collector.positions.keys)
    }

    /// Records a referenced name, including the member in `a.member` and the component in `\.member`.
    ///
    /// - Parameter node: The reference.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        record(node.baseName.text, at: node.position)
    }

    /// Records a type name, such as `Foo` in `let x: Foo`.
    ///
    /// - Parameter node: The type.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, at: node.position)
    }

    /// Records a nested type name, such as `Bar` in `Foo.Bar`.
    ///
    /// - Parameter node: The member type.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, at: node.name.position)
    }

    /// Records the name a shorthand `if let x` / `guard let x` binding unwraps.
    ///
    /// - Parameter node: The optional binding.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: OptionalBindingConditionSyntax) -> SyntaxVisitorContinueKind {
        guard node.initializer == nil, let name = node.pattern.as(IdentifierPatternSyntax.self) else {
            return .visitChildren
        }
        return record(name.identifier.text, at: name.position)
    }

    /// Adds one use of a name.
    ///
    /// - Parameters:
    ///   - name: The name used.
    ///   - position: Where it's used.
    /// - Returns: `.visitChildren`.
    private func record(_ name: String, at position: AbsolutePosition) -> SyntaxVisitorContinueKind {
        positions[name, default: []].append(position)
        return .visitChildren
    }
}
