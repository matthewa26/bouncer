import SwiftSyntax
import BouncerRules

/// Small syntax questions the design-smell collectors ask about an expression: is it called, assigned,
/// mutated, in a condition, or a statement of its own.
enum SwiftDesignSyntax {
    private static let compoundOperators: Set<String> = [
        "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>=", "&+=", "&-=", "&*=", "??="
    ]

    /// Strips `?` and `!` from an expression.
    ///
    /// - Parameter expression: Any expression.
    /// - Returns: The expression they wrap, or the expression itself.
    static func unwrapped(_ expression: ExprSyntax) -> ExprSyntax {
        var current = expression
        while let inner = current.as(OptionalChainingExprSyntax.self)?.expression
                ?? current.as(ForceUnwrapExprSyntax.self)?.expression {
            current = inner
        }
        return current
    }

    /// Reports whether an expression is a constant: a literal without interpolation, or an implicit enum
    /// case such as `.visitChildren`.
    ///
    /// - Parameter expression: Any expression.
    /// - Returns: Whether it's a constant.
    static func isConstant(_ expression: ExprSyntax) -> Bool {
        if expression.is(BooleanLiteralExprSyntax.self) || expression.is(IntegerLiteralExprSyntax.self)
            || expression.is(FloatLiteralExprSyntax.self) || expression.is(NilLiteralExprSyntax.self) { return true }
        if let string = expression.as(StringLiteralExprSyntax.self) {
            return string.segments.allSatisfy { $0.is(StringSegmentSyntax.self) }
        }
        return expression.as(MemberAccessExprSyntax.self).map { $0.base == nil } ?? false
    }

    /// Reports whether an expression is what a call calls.
    ///
    /// - Parameter node: The expression.
    /// - Returns: Whether its parent is a call with it as the callee.
    static func isCallee(_ node: some ExprSyntaxProtocol) -> Bool {
        node.parent?.as(FunctionCallExprSyntax.self)?.calledExpression.id == node.id
    }

    /// Classifies how a reference to a field touches it: assigned outright, changed through its old value
    /// (a compound assignment, `&field`, assigning one of its members, or a mutating call on it), or read.
    ///
    /// - Parameters:
    ///   - expression: The reference, `self.field` or a bare `field`.
    ///   - field: The field's name.
    /// - Returns: The kind of access.
    static func accessKind(of expression: ExprSyntax, field: String) -> FieldAccess.Kind {
        let current = outermostUnwrap(Syntax(expression))
        if current.parent?.is(InOutExprSyntax.self) == true { return .mutate }
        if let member = current.parent?.as(MemberAccessExprSyntax.self), member.base?.id == current.id {
            let isMutatorCall = DesignVocabulary.mutatorNames.contains(member.declName.baseName.text)
            if isCallee(member) { return isMutatorCall ? .mutate : .read }
            return assignmentOperator(of: outermostUnwrap(Syntax(member))) == nil ? .read : .mutate
        }
        guard let operation = assignmentOperator(of: current) else { return .read }
        return operation == "=" && !rightSide(of: current, mentions: field) ? .assign : .mutate
    }

    /// Climbs from an expression through any `?` and `!` wrapped around it.
    ///
    /// - Parameter node: The expression.
    /// - Returns: The outermost unwrapping expression, or the expression itself.
    private static func outermostUnwrap(_ node: Syntax) -> Syntax {
        var current = node
        while let parent = current.parent,
              parent.is(OptionalChainingExprSyntax.self) || parent.is(ForceUnwrapExprSyntax.self) {
            current = parent
        }
        return current
    }

    /// Finds the assignment operator an expression is the left side of, in an unfolded sequence.
    ///
    /// - Parameter node: The expression.
    /// - Returns: `=` or a compound operator such as `+=`, or `nil` if it isn't assigned.
    static func assignmentOperator(of node: Syntax) -> String? {
        guard let list = node.parent?.as(ExprListSyntax.self), list.first?.id == node.id, list.count > 2 else {
            return nil
        }
        let operation = list[list.index(after: list.startIndex)]
        if operation.is(AssignmentExprSyntax.self) { return "=" }
        let text = operation.as(BinaryOperatorExprSyntax.self)?.operator.text ?? ""
        return compoundOperators.contains(text) ? text : nil
    }

    /// Reports whether an assignment's right side names a field, as `x = x + 1` does.
    ///
    /// - Parameters:
    ///   - node: The assignment's left side.
    ///   - field: The field's name.
    /// - Returns: Whether any token after the operator is the field's name.
    private static func rightSide(of node: Syntax, mentions field: String) -> Bool {
        guard let list = node.parent?.as(ExprListSyntax.self) else { return false }
        return list.dropFirst(2).contains { $0.tokens(viewMode: .sourceAccurate).contains { $0.text == field } }
    }

    /// Reports whether a member access doesn't read another object's data for feature envy and ATFD: it's
    /// assigned with `=`, or it's an argument copied as is into an uppercase constructor call, as a mapper does.
    ///
    /// - Parameter node: The member access.
    /// - Returns: Whether it's a write or a straight copy.
    static func isWriteOrCopy(_ node: MemberAccessExprSyntax) -> Bool {
        let outer = outermostUnwrap(Syntax(node))
        if assignmentOperator(of: outer) == "=" { return true }
        guard let argument = outer.parent?.as(LabeledExprSyntax.self),
              let call = argument.parent?.parent?.as(FunctionCallExprSyntax.self) else { return false }
        let callee = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
        return callee?.first?.isUppercase == true
    }

    /// Reports whether an assigned expression's assignment is a statement directly in a body.
    ///
    /// - Parameters:
    ///   - expression: The assignment's left side.
    ///   - body: The method's body.
    /// - Returns: Whether the assignment isn't nested in a branch, loop, or closure.
    static func isTopLevelStatement(_ expression: ExprSyntax, in body: CodeBlockSyntax) -> Bool {
        let sequence = outermostUnwrap(Syntax(expression)).parent?.parent
        guard sequence?.is(SequenceExprSyntax.self) == true, let item = sequence?.parent else { return false }
        return item.is(CodeBlockItemSyntax.self) && item.parent?.parent?.id == body.id
    }

    /// Reports whether a node sits in an `if` or `guard` condition.
    ///
    /// - Parameter node: Any node.
    /// - Returns: Whether a condition element of an `if` or `guard` contains it, outside any nested block.
    static func isInCondition(_ node: some SyntaxProtocol) -> Bool {
        var current = node.parent
        while let next = current, !next.is(CodeBlockSyntax.self) {
            if next.is(ConditionElementSyntax.self), let owner = next.parent?.parent {
                return owner.is(IfExprSyntax.self) || owner.is(GuardStmtSyntax.self)
            }
            current = next.parent
        }
        return false
    }

    /// Reports whether a node belongs to a body itself rather than to a closure or function inside it.
    ///
    /// - Parameters:
    ///   - body: The body.
    ///   - node: A node inside it.
    /// - Returns: Whether no closure or nested function encloses the node within the body.
    static func isDirectlyIn(_ body: CodeBlockSyntax, _ node: some SyntaxProtocol) -> Bool {
        var current = node.parent
        while let next = current, next.id != body.id {
            if next.is(ClosureExprSyntax.self) || next.is(FunctionDeclSyntax.self) { return false }
            current = next.parent
        }
        return current != nil
    }
}

/// Collects the names a body binds itself: locals, loop and pattern variables, closure parameters, and
/// nested functions' parameters, but not an `if let field` shorthand, which reads the field.
final class SwiftLocalNames: SyntaxVisitor {
    private(set) var names: Set<String> = []

    /// Collects a body's local names.
    ///
    /// - Parameter body: The body.
    /// - Returns: The names it binds.
    static func names(in body: some SyntaxProtocol) -> Set<String> {
        let collector = SwiftLocalNames(viewMode: .sourceAccurate)
        collector.walk(body)
        return collector.names
    }

    /// Records a bound name, unless it's an `if let` shorthand.
    ///
    /// - Parameter node: The pattern.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
        let binding = node.parent?.as(OptionalBindingConditionSyntax.self)
        if binding == nil || binding?.initializer != nil { names.insert(node.identifier.text) }
        return .visitChildren
    }

    /// Records a closure's shorthand parameter.
    ///
    /// - Parameter node: The parameter.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ClosureShorthandParameterSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.name.text)
        return .visitChildren
    }

    /// Records a closure's parameter.
    ///
    /// - Parameter node: The parameter.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ClosureParameterSyntax) -> SyntaxVisitorContinueKind {
        names.insert((node.secondName ?? node.firstName).text)
        return .visitChildren
    }

    /// Records a nested function's parameter.
    ///
    /// - Parameter node: The parameter.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        names.insert((node.secondName ?? node.firstName).text)
        return .visitChildren
    }
}
