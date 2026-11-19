import SwiftSyntax
import BouncerRules

/// Reads one method's `MethodDesign`: its own members and fields, other objects' data, its calls, and
/// whether it returns a value.
///
/// A bare name counts as an own member when the type declares it and the method doesn't bind it as a
/// parameter or local. Other objects are lowercase names (or `self.field`) whose members it reaches.
final class SwiftMethodDesign: SyntaxVisitor {
    /// The type's own names: every member, and the subset that are fields.
    struct Members {
        let all: Set<String>
        let fields: Set<String>
    }

    private let members: Members
    private let locals: Set<String>
    private let body: CodeBlockSyntax
    private(set) var ownMembers: Set<String> = []
    private(set) var foreignData: [String: Set<String>] = [:]
    private(set) var fieldAccesses: [FieldAccess] = []
    private(set) var calls: Set<String> = []
    private(set) var conditionFields: Set<String> = []
    private(set) var returnsSelf = false
    /// Whether it has a `return` of its own and every one returns a constant, such as `true` or `.done`.
    private(set) var returnsOnlyConstants = false
    private var returnsComputedValue = false

    /// Measures a method body.
    ///
    /// - Parameters:
    ///   - body: The method's body.
    ///   - parameters: The method's parameter names.
    ///   - members: The type's member and field names.
    init(body: CodeBlockSyntax, parameters: Set<String>, members: Members) {
        self.members = members
        self.body = body
        self.locals = parameters.union(SwiftLocalNames.names(in: body))
        super.init(viewMode: .sourceAccurate)
        walk(body)
    }

    /// Records an own member, another object's data, or a call reached through `.`.
    ///
    /// - Parameter node: The member access.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.declName.baseName.text
        if SwiftDesignSyntax.isCallee(node) { calls.insert(name) }
        guard let base = node.base.map(SwiftDesignSyntax.unwrapped) else { return .visitChildren }
        if base.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind == .keyword(.self) {
            recordOwn(name, at: ExprSyntax(node))
        } else if let receiver = receiverName(of: base), !SwiftDesignSyntax.isWriteOrCopy(node) {
            recordForeign(node, of: receiver)
        }
        return .visitChildren
    }

    /// Records a read of another object's member, if it's that object's data.
    ///
    /// - Parameters:
    ///   - node: The member access.
    ///   - receiver: The other object's name.
    private func recordForeign(_ node: MemberAccessExprSyntax, of receiver: String) {
        let name = node.declName.baseName.text
        guard DesignVocabulary.isForeignData(name, isCalled: SwiftDesignSyntax.isCallee(node)) else { return }
        foreignData[receiver, default: []].insert(name)
    }

    /// Records a bare name that's an own member, or a call to a function.
    ///
    /// - Parameter node: The reference.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.parent?.as(MemberAccessExprSyntax.self)?.declName.id != node.id else { return .visitChildren }
        let name = node.baseName.text
        if SwiftDesignSyntax.isCallee(node), name.first?.isLowercase == true { calls.insert(name) }
        if members.all.contains(name), !locals.contains(name) { recordOwn(name, at: ExprSyntax(node)) }
        return .visitChildren
    }

    /// Records a field read by Swift's `if let field` shorthand, which names the field without an expression.
    ///
    /// - Parameter node: The optional binding.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: OptionalBindingConditionSyntax) -> SyntaxVisitorContinueKind {
        guard node.initializer == nil, let name = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              members.fields.contains(name) else { return .visitChildren }
        ownMembers.insert(name)
        fieldAccesses.append(FieldAccess(field: name, kind: .read))
        conditionFields.insert(name)
        return .visitChildren
    }

    /// Notes what the method's own `return`s give back: `self`, which makes it fluent, or only constants such
    /// as `true` or `.visitChildren`, which make the result a status rather than a query's answer.
    ///
    /// - Parameter node: The return statement.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
        guard SwiftDesignSyntax.isDirectlyIn(body, node) else { return .visitChildren }
        let returned = node.expression?.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind
        if returned == .keyword(.self) { returnsSelf = true }
        returnsComputedValue = returnsComputedValue || !(node.expression.map(SwiftDesignSyntax.isConstant) ?? true)
        returnsOnlyConstants = !returnsComputedValue
        return .visitChildren
    }

    /// Records an own member and, for a field, how this reference touches it.
    ///
    /// - Parameters:
    ///   - name: The own member's name.
    ///   - expression: The reference, `self.name` or a bare `name`.
    private func recordOwn(_ name: String, at expression: ExprSyntax) {
        ownMembers.insert(name)
        guard members.fields.contains(name) else { return }
        let kind = SwiftDesignSyntax.accessKind(of: expression, field: name)
        let isTopLevel = kind == .assign && SwiftDesignSyntax.isTopLevelStatement(expression, in: body)
        fieldAccesses.append(FieldAccess(field: name, kind: kind, isTopLevel: isTopLevel))
        if SwiftDesignSyntax.isInCondition(expression) { conditionFields.insert(name) }
    }

    /// Names the object a member access's base is: a lowercase local, parameter, or field, or `self.field`.
    ///
    /// - Parameter base: The member access's base, unwrapped.
    /// - Returns: The object's name, or `nil` for a type, `self`, a literal, or a longer expression.
    private func receiverName(of base: ExprSyntax) -> String? {
        if let reference = base.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            guard reference.baseName.tokenKind == .identifier(name), name.first?.isLowercase == true else { return nil }
            return name
        }
        guard let member = base.as(MemberAccessExprSyntax.self),
              member.base?.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind == .keyword(.self) else { return nil }
        return member.declName.baseName.text
    }
}
