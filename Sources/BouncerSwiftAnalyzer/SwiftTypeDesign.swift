import SwiftSyntax
import BouncerRules

/// Measures a Swift class or struct's `TypeDesign`: the other types it names, its fields, and what each
/// of its methods and initializers does with its own members and with other objects.
enum SwiftTypeDesign {
    /// Measures a type declaration.
    ///
    /// - Parameters:
    ///   - node: The class or struct declaration.
    ///   - name: Its name.
    ///   - converter: Converts syntax positions to line numbers.
    /// - Returns: Its design facts.
    static func design(
        of node: some DeclGroupSyntax, name: String, converter: SourceLocationConverter
    ) -> TypeDesign {
        let line = { (syntax: Syntax) in converter.location(for: syntax.positionAfterSkippingLeadingTrivia).line }
        let members = node.memberBlock, fields = SwiftCohesion.propertyNames(in: members)
        let functionNames = members.members.compactMap { $0.decl.as(FunctionDeclSyntax.self)?.name.text }
        let names = SwiftMethodDesign.Members(all: fields.union(functionNames), fields: fields)
        return TypeDesign(
            referencedTypes: SwiftTypeReferences.referenced(by: node, name: name),
            methods: members.members.compactMap { method($0.decl, members: names, line: line) },
            fields: fieldDeclarations(in: members, line: line)
        )
    }

    /// Measures one member if it's a method or initializer with a body.
    ///
    /// - Parameters:
    ///   - decl: The member's declaration.
    ///   - members: The type's member and field names.
    ///   - line: Finds a node's 1-indexed line.
    /// - Returns: Its design facts, or `nil` for any other member.
    private static func method(
        _ decl: DeclSyntax, members: SwiftMethodDesign.Members, line: (Syntax) -> Int
    ) -> MethodDesign? {
        if let function = decl.as(FunctionDeclSyntax.self), let body = function.body {
            return design(of: function, body: body, members: members, line: line)
        }
        guard let initializer = decl.as(InitializerDeclSyntax.self), let body = initializer.body else { return nil }
        let visitor = measure(body, signature: initializer.signature, members: members)
        return MethodDesign(
            name: "init", line: line(Syntax(initializer.initKeyword)), kind: .initializer,
            ownMembers: visitor.ownMembers, fieldAccesses: visitor.fieldAccesses, calls: visitor.calls
        )
    }

    /// Measures a method with a body.
    ///
    /// - Parameters:
    ///   - function: The method.
    ///   - body: Its body.
    ///   - members: The type's member and field names.
    ///   - line: Finds a node's 1-indexed line.
    /// - Returns: Its design facts.
    private static func design(
        of function: FunctionDeclSyntax, body: CodeBlockSyntax, members: SwiftMethodDesign.Members,
        line: (Syntax) -> Int
    ) -> MethodDesign {
        let visitor = measure(body, signature: function.signature, members: members)
        let has = { (keyword: Keyword) in hasModifier(keyword, function.modifiers) }
        return MethodDesign(
            name: function.name.text, line: line(Syntax(function.name)), kind: isTypeLevel(function.modifiers)
                ? .typeLevel : .instance, ownMembers: visitor.ownMembers, foreignData: visitor.foreignData,
            fieldAccesses: visitor.fieldAccesses, calls: visitor.calls,
            returnsValue: returnsValue(function, walk: visitor),
            conditionFields: visitor.conditionFields, isMutating: has(.mutating), isOverride: has(.override)
        )
    }

    /// Walks a method or initializer body.
    ///
    /// - Parameters:
    ///   - body: The body.
    ///   - signature: The declaration's signature, for its parameter names.
    ///   - members: The type's member and field names.
    /// - Returns: The finished walk.
    private static func measure(
        _ body: CodeBlockSyntax, signature: FunctionSignatureSyntax, members: SwiftMethodDesign.Members
    ) -> SwiftMethodDesign {
        let parameters = signature.parameterClause.parameters.map { ($0.secondName ?? $0.firstName).text }
        return SwiftMethodDesign(body: body, parameters: Set(parameters), members: members)
    }

    /// Reports whether a method returns a computed value: a result type other than `Void`, `Never`, or
    /// `Self`, no `@discardableResult`, no `return self`, and not only constant `return`s, which give a status.
    ///
    /// - Parameters:
    ///   - function: The method.
    ///   - walk: The walk of its body, which knows what its `return`s give back.
    /// - Returns: Whether callers get a value they're meant to use.
    private static func returnsValue(_ function: FunctionDeclSyntax, walk: SwiftMethodDesign) -> Bool {
        guard let type = function.signature.returnClause?.type.trimmedDescription, !walk.returnsSelf,
              !walk.returnsOnlyConstants else { return false }
        let isDiscardable = function.attributes.contains {
            $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "discardableResult"
        }
        return !isDiscardable && !["Void", "()", "Never", "Self"].contains(type)
    }

    /// Lists a type's instance fields, marking the ones that could be temporary.
    ///
    /// - Parameters:
    ///   - members: The type's member block.
    ///   - line: Finds a node's 1-indexed line.
    /// - Returns: One declaration per named binding.
    private static func fieldDeclarations(in members: MemberBlockSyntax, line: (Syntax) -> Int) -> [FieldDeclaration] {
        let usedElsewhere = namesOutsideMethods(members)
        let variables = members.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }
        return variables.filter { !isTypeLevel($0.modifiers) }.flatMap { variable in
            variable.bindings.compactMap { binding in
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return nil }
                let isCandidate = isTemporaryCandidate(variable, binding) && !usedElsewhere.contains(name)
                return field(name, binding, isCandidate: isCandidate, line: line)
            }
        }
    }

    /// Describes one field binding.
    ///
    /// - Parameters:
    ///   - name: The field's name.
    ///   - binding: Its binding, for its line and declared type.
    ///   - isCandidate: Whether it could be a temporary field.
    ///   - line: Finds a node's 1-indexed line.
    /// - Returns: The field declaration.
    private static func field(
        _ name: String, _ binding: PatternBindingSyntax, isCandidate: Bool, line: (Syntax) -> Int
    ) -> FieldDeclaration {
        FieldDeclaration(
            name: name, line: line(Syntax(binding)), typeName: binding.typeAnnotation?.type.trimmedDescription,
            isTemporaryCandidate: isCandidate
        )
    }

    /// Reports whether a field could be temporary: a `private var` with no value (or `nil`), stored, and
    /// without an attribute, `lazy`, `weak`, or `unowned`.
    ///
    /// - Parameters:
    ///   - variable: The field's declaration.
    ///   - binding: The field's binding within it.
    /// - Returns: Whether it's a candidate.
    private static func isTemporaryCandidate(_ variable: VariableDeclSyntax, _ binding: PatternBindingSyntax) -> Bool {
        let value = binding.initializer?.value
        let isUnset = value == nil || value?.is(NilLiteralExprSyntax.self) == true
        let isPlain = !variable.modifiers.contains { [.keyword(.lazy), .keyword(.weak), .keyword(.unowned)]
            .contains($0.name.tokenKind) }
        return variable.bindingSpecifier.tokenKind == .keyword(.var) && hasModifier(.private, variable.modifiers)
            && isPlain && variable.attributes.isEmpty && binding.accessorBlock == nil && isUnset
    }

    /// Collects the identifiers used by members other than methods and initializers: computed properties,
    /// property observers and initial values, subscripts, `deinit`, and nested types.
    ///
    /// - Parameter members: The type's member block.
    /// - Returns: Every identifier those members mention.
    private static func namesOutsideMethods(_ members: MemberBlockSyntax) -> Set<String> {
        let parts = members.members.map(\.decl).flatMap { decl -> [Syntax] in
            if decl.is(FunctionDeclSyntax.self) || decl.is(InitializerDeclSyntax.self) { return [] }
            guard let variable = decl.as(VariableDeclSyntax.self) else { return [Syntax(decl)] }
            return variable.bindings.flatMap { [$0.accessorBlock.map(Syntax.init), $0.initializer.map(Syntax.init)] }
                .compactMap { $0 }
        }
        return Set(parts.flatMap { $0.tokens(viewMode: .sourceAccurate).map(\.text) })
    }

    /// Reports whether a declaration is `static` or `class`.
    ///
    /// - Parameter modifiers: Its modifiers.
    /// - Returns: Whether it belongs to the type rather than its instances.
    private static func isTypeLevel(_ modifiers: DeclModifierListSyntax) -> Bool {
        hasModifier(.static, modifiers) || hasModifier(.class, modifiers)
    }

    /// Reports whether a declaration has a modifier.
    ///
    /// - Parameters:
    ///   - keyword: The modifier's keyword.
    ///   - modifiers: The declaration's modifiers.
    /// - Returns: Whether it's among them.
    private static func hasModifier(_ keyword: Keyword, _ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.tokenKind == .keyword(keyword) }
    }
}

/// Collects the type names a type declaration mentions, for CBO: type annotations (with their generic
/// arguments), its inheritance clause, uppercase constructor calls, and uppercase bases of member access.
final class SwiftTypeReferences: SyntaxVisitor {
    private var names: Set<String> = []
    private var excluded: Set<String> = ["Self"]

    /// Lists the other types a declaration names.
    ///
    /// - Parameters:
    ///   - node: The type declaration.
    ///   - name: Its name, which isn't counted.
    /// - Returns: The names, minus its own, its nested types', and every generic parameter's.
    static func referenced(by node: some DeclGroupSyntax, name: String) -> Set<String> {
        let collector = SwiftTypeReferences(viewMode: .sourceAccurate)
        collector.walk(node.memberBlock)
        node.inheritanceClause.map { collector.walk($0) }
        let generics = node.as(ClassDeclSyntax.self)?.genericParameterClause
            ?? node.as(StructDeclSyntax.self)?.genericParameterClause
        generics.map { collector.walk($0) }
        return collector.names.subtracting(collector.excluded).subtracting([name])
    }

    /// Records a named type.
    ///
    /// - Parameter node: The type.
    /// - Returns: `.visitChildren`, for its generic arguments.
    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.name.text)
        return .visitChildren
    }

    /// Records the type an uppercase call constructs.
    ///
    /// - Parameter node: The call.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        record(node.calledExpression)
        return .visitChildren
    }

    /// Records the type an uppercase member-access base names, as in `Parser.parse(x)`.
    ///
    /// - Parameter node: The member access.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        node.base.map(record)
        return .visitChildren
    }

    /// Leaves a generic parameter's name out.
    ///
    /// - Parameter node: The generic parameter.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: GenericParameterSyntax) -> SyntaxVisitorContinueKind {
        excluded.insert(node.name.text)
        return .visitChildren
    }

    /// Leaves a nested class out, along with everything in it.
    ///
    /// - Parameter node: The nested class.
    /// - Returns: `.skipChildren`.
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { nested(node.name) }

    /// Leaves a nested struct out, along with everything in it.
    ///
    /// - Parameter node: The nested struct.
    /// - Returns: `.skipChildren`.
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { nested(node.name) }

    /// Leaves a nested enum out, along with everything in it.
    ///
    /// - Parameter node: The nested enum.
    /// - Returns: `.skipChildren`.
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { nested(node.name) }

    /// Leaves a nested type alias out.
    ///
    /// - Parameter node: The type alias.
    /// - Returns: `.skipChildren`.
    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind { nested(node.name) }

    /// Leaves an associated type out.
    ///
    /// - Parameter node: The associated type.
    /// - Returns: `.skipChildren`.
    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind { nested(node.name) }

    /// Excludes a nested declaration's name and skips its body.
    ///
    /// - Parameter name: The declared name.
    /// - Returns: `.skipChildren`.
    private func nested(_ name: TokenSyntax) -> SyntaxVisitorContinueKind {
        excluded.insert(name.text)
        return .skipChildren
    }

    /// Records an expression's name if it's an uppercase reference, which names a type.
    ///
    /// - Parameter expression: A callee or member-access base.
    private func record(_ expression: ExprSyntax) {
        guard let name = expression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              name.first?.isUppercase == true else { return }
        names.insert(name)
    }
}
