import SwiftSyntax
import BouncerCore

/// Collects each Swift type's collaboration facts: members it reads on parameters, properties, and locals
/// whose type is written (or constructed), and the types it constructs and keeps in properties.
///
/// Names are bound per type, not per scope: a name bound to two different types anywhere in the type is
/// dropped rather than guessed.
final class SwiftCollaborationCollector: SyntaxVisitor {
    private var frames: [CollaborationBuilder] = []
    private(set) var facts: [CollaborationFact] = []
    private let converter: SourceLocationConverter

    /// Creates a collector for a parsed file.
    ///
    /// - Parameter parsed: The parsed file, for its line converter.
    init(_ parsed: Parsed) {
        converter = parsed.converter
        super.init(viewMode: .sourceAccurate)
    }

    /// Enters a class.
    ///
    /// - Parameter node: The class.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text, node) }

    /// Enters a struct.
    ///
    /// - Parameter node: The struct.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text, node) }

    /// Enters an enum.
    ///
    /// - Parameter node: The enum.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text, node) }

    /// Enters an actor.
    ///
    /// - Parameter node: The actor.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text, node) }

    /// Enters an extension, as its extended type.
    ///
    /// - Parameter node: The extension.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(FactText.typeName(node.extendedType.trimmedDescription), node)
    }

    /// Skips a protocol, whose requirements have no bodies.
    ///
    /// - Parameter node: The protocol.
    /// - Returns: `.skipChildren`.
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

    /// Leaves a class.
    ///
    /// - Parameter node: The class.
    override func visitPost(_ node: ClassDeclSyntax) { leave() }

    /// Leaves a struct.
    ///
    /// - Parameter node: The struct.
    override func visitPost(_ node: StructDeclSyntax) { leave() }

    /// Leaves an enum.
    ///
    /// - Parameter node: The enum.
    override func visitPost(_ node: EnumDeclSyntax) { leave() }

    /// Leaves an actor.
    ///
    /// - Parameter node: The actor.
    override func visitPost(_ node: ActorDeclSyntax) { leave() }

    /// Leaves an extension.
    ///
    /// - Parameter node: The extension.
    override func visitPost(_ node: ExtensionDeclSyntax) { leave() }

    /// Binds each name a `let`/`var` declares to its written type, or to the type its value constructs, and
    /// records a type a stored property constructs.
    ///
    /// - Parameter node: The declaration.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let isProperty = node.parent?.is(MemberBlockItemSyntax.self) == true
        for binding in node.bindings {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
            let constructed = binding.initializer.flatMap { Self.constructedType($0.value) }
            bind(name, binding.typeAnnotation.map { $0.type.trimmedDescription } ?? constructed)
            if isProperty { frames.last?.property(name) }
            if isProperty, let constructed { frames.last?.construct(constructed) }
        }
        return .visitChildren
    }

    /// Records `self.name = Foo(…)` and `name = Foo(…)`, which keep a constructed collaborator when `name` is
    /// a stored property.
    ///
    /// - Parameter node: The unfolded expression sequence.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)
        guard elements.count == 3, elements[1].is(AssignmentExprSyntax.self),
              let type = Self.constructedType(elements[2]), let target = Self.assigned(elements[0]) else {
            return .visitChildren
        }
        bind(target.name, type)
        if target.isSelf { frames.last?.construct(type) } else { frames.last?.assign(target.name, type) }
        return .visitChildren
    }

    /// Names the target of an assignment: a bare name, or `self.name`.
    ///
    /// - Parameter expression: The assignment's left side.
    /// - Returns: The name and whether it was written `self.name`, or `nil` for any other target.
    private static func assigned(_ expression: ExprSyntax) -> (name: String, isSelf: Bool)? {
        if let name = expression.as(DeclReferenceExprSyntax.self)?.baseName.text { return (name, false) }
        guard let member = expression.as(MemberAccessExprSyntax.self),
              member.base?.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind == .keyword(.self) else { return nil }
        return (member.declName.baseName.text, true)
    }

    /// Binds a parameter's name to its written type.
    ///
    /// - Parameter node: The parameter.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        let type = node.type.as(AttributedTypeSyntax.self)?.baseType ?? node.type
        bind((node.secondName ?? node.firstName).text, type.trimmedDescription)
        return .visitChildren
    }

    /// Records a member read on a bare name or on `self.name`.
    ///
    /// - Parameter node: The member access.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let member = node.declName.baseName.text
        if let base = node.base?.as(DeclReferenceExprSyntax.self) {
            frames.last?.access(base.baseName.text, member)
        } else if let base = node.base?.as(MemberAccessExprSyntax.self),
                  base.base?.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind == .keyword(.self) {
            frames.last?.access(base.declName.baseName.text, member)
        }
        return .visitChildren
    }

    /// Names the type a call constructs: a call of a capitalized bare name.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The type's name, or `nil` if the expression isn't such a call.
    private static func constructedType(_ expression: ExprSyntax) -> String? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let callee = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              callee.first?.isUppercase == true else { return nil }
        return callee
    }

    /// Binds a name to a type in the innermost type being read.
    ///
    /// - Parameters:
    ///   - name: The name.
    ///   - written: The type as written, or `nil` if unknown.
    private func bind(_ name: String, _ written: String?) {
        guard let written else { return }
        frames.last?.bind(name, FactText.typeName(written))
    }

    /// Starts reading a type.
    ///
    /// - Parameters:
    ///   - owner: The type's name.
    ///   - node: Its declaration.
    /// - Returns: `.visitChildren`.
    private func enter(_ owner: String, _ node: some SyntaxProtocol) -> SyntaxVisitorContinueKind {
        let line = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        frames.append(CollaborationBuilder(owner: owner, line: line))
        return .visitChildren
    }

    /// Finishes reading a type and keeps its facts if it has any.
    private func leave() {
        guard let frame = frames.popLast(), let fact = frame.fact else { return }
        facts.append(fact)
    }
}
