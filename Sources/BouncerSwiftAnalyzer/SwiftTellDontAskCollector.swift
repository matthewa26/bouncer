import SwiftSyntax
import BouncerRules

/// Records each `if` that asks another object about its state and then changes that same object, for
/// `tell-dont-ask`: the condition reads a member of `self.field` or of a lowercase name the enclosing
/// function doesn't declare itself (a parameter, field, or global), and the `if`'s body assigns that same
/// member or calls its setter, as in `if account.balance >= x { account.balance -= x }`.
final class SwiftTellDontAskCollector: SyntaxVisitor {
    private let converter: SourceLocationConverter
    private(set) var markers: [CollectedMarker] = []

    /// Creates a collector for a parsed file.
    ///
    /// - Parameter converter: Converts syntax positions to line numbers.
    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    /// Records an `if` whose body tells an object it asked about in its condition.
    ///
    /// - Parameter node: The `if`.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        let told = SwiftObjectUses(node.conditions).reads.intersection(SwiftObjectUses(node.body).changes)
        let locals = told.isEmpty ? [] : localNames(around: node)
        guard told.contains(where: { !locals.contains($0.object) }) else { return .visitChildren }
        let line = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        markers.append(CollectedMarker(kind: .tellDontAsk, line: line))
        return .visitChildren
    }

    /// Lists the locals of the function or initializer around a node: values it builds itself, which
    /// aren't another object it was handed.
    ///
    /// - Parameter node: A node inside a function.
    /// - Returns: The enclosing body's local names, or none at file scope.
    private func localNames(around node: some SyntaxProtocol) -> Set<String> {
        var current = node.parent
        while let next = current {
            if let body = next.as(FunctionDeclSyntax.self)?.body ?? next.as(InitializerDeclSyntax.self)?.body {
                return SwiftLocalNames.names(in: body)
            }
            current = next.parent
        }
        return []
    }
}

/// The other objects' state a subtree reads and changes, by the object's source text and the state's
/// name (`DesignVocabulary.stateName`, so `getBalance()` reads what `balance = x` changes).
final class SwiftObjectUses: SyntaxVisitor {
    private(set) var reads: Set<ObjectState> = []
    private(set) var changes: Set<ObjectState> = []

    /// Walks a subtree.
    ///
    /// - Parameter node: The subtree.
    init(_ node: some SyntaxProtocol) {
        super.init(viewMode: .sourceAccurate)
        walk(node)
    }

    /// Records the object a member access reads, and whether the access assigns it or calls a setter.
    ///
    /// - Parameter node: The member access.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.declName.baseName.text
        guard let object = node.base.map(SwiftDesignSyntax.unwrapped), Self.isOtherObject(object),
              !DesignVocabulary.isLibraryAccessor(name) else { return .visitChildren }
        let state = ObjectState(object: object.trimmedDescription, state: DesignVocabulary.stateName(of: name))
        reads.insert(state)
        let isSetterCall = SwiftDesignSyntax.isCallee(node) && DesignVocabulary.isSetter(name)
        if isSetterCall || SwiftDesignSyntax.assignmentOperator(of: Syntax(node)) != nil { changes.insert(state) }
        return .visitChildren
    }

    /// Reports whether an expression names another object: a lowercase name other than `self`, or `self.field`.
    ///
    /// - Parameter expression: A member access's base.
    /// - Returns: Whether it's another object.
    private static func isOtherObject(_ expression: ExprSyntax) -> Bool {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName
            return name.tokenKind == .identifier(name.text) && name.text.first?.isLowercase == true
        }
        guard let member = expression.as(MemberAccessExprSyntax.self) else { return false }
        return member.base?.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind == .keyword(.self)
    }
}
