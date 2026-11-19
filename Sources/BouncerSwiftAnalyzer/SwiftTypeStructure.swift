import SwiftSyntax
import BouncerRules

/// Measures a Swift class or struct's `TypeStructure`: method field use, complexity, and delegation.
enum SwiftTypeStructure {
    /// Measures a type declaration.
    ///
    /// - Parameters:
    ///   - node: The class or struct declaration.
    ///   - isExtended: Whether an extension in the same file adds to it, which may add a conformance.
    /// - Returns: Its structure.
    static func structure(of node: some DeclGroupSyntax, isExtended: Bool) -> TypeStructure {
        let members = node.memberBlock
        let fields = SwiftCohesion.propertyNames(in: members), names = SwiftCohesion.memberNames(members)
        return TypeStructure(
            methods: SwiftCohesion.instanceMethods(in: members).map { graphMethod($0, names: names, fields: fields) },
            fieldNames: fields, methodComplexities: complexities(in: members), isPlain: isPlain(node),
            isComplete: !isExtended
        )
    }

    /// Describes one method for the method-field graph.
    ///
    /// - Parameters:
    ///   - method: The method.
    ///   - names: The type's member names.
    ///   - fields: The type's property names.
    /// - Returns: Its graph entry.
    private static func graphMethod(
        _ method: FunctionDeclSyntax, names: Set<String>, fields: Set<String>
    ) -> CohesionGraph.Method {
        CohesionGraph.Method(
            name: method.name.text, references: SwiftCohesion.references(in: method, to: names),
            delegate: delegate(of: method, fields: fields)
        )
    }

    /// Measures the cyclomatic complexity of every method and initializer with a body.
    ///
    /// - Parameter members: The type's member block.
    /// - Returns: One complexity per method or initializer.
    private static func complexities(in members: MemberBlockSyntax) -> [Int] {
        members.members.compactMap { member -> CodeBlockSyntax? in
            member.decl.as(FunctionDeclSyntax.self)?.body ?? member.decl.as(InitializerDeclSyntax.self)?.body
        }.map { body in
            let counter = BranchCounter()
            counter.walk(body)
            return counter.count + 1
        }
    }

    /// Reports whether a declaration isn't `public`/`open` and has no inheritance clause, attribute, or
    /// generic parameter.
    ///
    /// - Parameter node: The declaration.
    /// - Returns: Whether it's plain.
    private static func isPlain(_ node: some DeclGroupSyntax) -> Bool {
        let generic = node.as(ClassDeclSyntax.self)?.genericParameterClause
            ?? node.as(StructDeclSyntax.self)?.genericParameterClause
        let isPublic = SwiftDeclarationSummaryBuilder.visibility(of: node.modifiers) == .public
        return !isPublic && node.inheritanceClause == nil && node.attributes.isEmpty && generic == nil
    }

    /// Finds the field a method does nothing but forward to: its only statement calls the same-named
    /// method on a field, as in `func load() throws { try store.load() }`.
    ///
    /// - Parameters:
    ///   - method: The method.
    ///   - fields: The type's property names.
    /// - Returns: The field, or `nil` if the method does anything else.
    static func delegate(of method: FunctionDeclSyntax, fields: Set<String>) -> String? {
        guard let statements = method.body?.statements, statements.count == 1, let item = statements.first,
              let call = calledExpression(item.item)?.as(MemberAccessExprSyntax.self),
              call.declName.baseName.text == method.name.text, let base = call.base else { return nil }
        let field = base.as(DeclReferenceExprSyntax.self)?.baseName.text ?? selfMember(base)
        return field.flatMap { fields.contains($0) ? $0 : nil }
    }

    /// Unwraps a statement to the callee of the call it makes, through `return`, `try`, and `await`.
    ///
    /// - Parameter item: The statement.
    /// - Returns: The called expression, or `nil` if the statement isn't a call.
    private static func calledExpression(_ item: CodeBlockItemSyntax.Item) -> ExprSyntax? {
        var expression = statementExpression(item)
        while let wrapped = expression?.as(TryExprSyntax.self)?.expression
                ?? expression?.as(AwaitExprSyntax.self)?.expression {
            expression = wrapped
        }
        return expression?.as(FunctionCallExprSyntax.self)?.calledExpression
    }

    /// Reads the expression a statement evaluates or returns.
    ///
    /// - Parameter item: The statement.
    /// - Returns: The expression, or `nil` for a declaration or other statement.
    private static func statementExpression(_ item: CodeBlockItemSyntax.Item) -> ExprSyntax? {
        switch item {
        case .expr(let value): return value
        case .stmt(let statement):
            return statement.as(ReturnStmtSyntax.self)?.expression
                ?? statement.as(ExpressionStmtSyntax.self)?.expression
        default: return nil
        }
    }

    /// Reads the member name from `self.name`.
    ///
    /// - Parameter expression: Any expression.
    /// - Returns: The member, or `nil` if it isn't a `self.` access.
    private static func selfMember(_ expression: ExprSyntax) -> String? {
        guard let member = expression.as(MemberAccessExprSyntax.self),
              member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "self" else { return nil }
        return member.declName.baseName.text
    }
}
