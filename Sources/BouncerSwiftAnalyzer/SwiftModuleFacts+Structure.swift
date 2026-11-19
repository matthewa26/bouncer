import SwiftSyntax
import BouncerCore

/// Collects a Swift file's structure facts: its types with their supertypes, stored properties, and
/// methods; its functions with their parameters; and its `switch` subjects.
final class SwiftStructureCollector: SyntaxVisitor {
    private var types: [TypeFact] = []
    private var functions: [FunctionFact] = []
    private var switches: [SwitchFact] = []
    private var enclosingTypes: [String] = []
    private let converter: SourceLocationConverter

    private let isGenerated: Bool

    /// The collected facts, with collaboration facts gathered separately.
    ///
    /// - Parameter collaborations: Each type's collaboration facts.
    /// - Returns: The file's structure facts.
    func structure(with collaborations: [CollaborationFact] = []) -> StructureFacts {
        StructureFacts(
            types: types, functions: functions, switches: switches, collaborations: collaborations,
            isGenerated: isGenerated
        )
    }

    /// Creates a collector for a parsed file.
    ///
    /// - Parameter parsed: The parsed file, for its line converter and header.
    init(_ parsed: Parsed) {
        converter = parsed.converter
        isGenerated = FactText.isGenerated(parsed.file.contents)
        super.init(viewMode: .sourceAccurate)
    }

    /// Records a class.
    ///
    /// - Parameter node: The class.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, name: node.name.text, kind: .class)
    }

    /// Records a struct.
    ///
    /// - Parameter node: The struct.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, name: node.name.text, kind: .struct)
    }

    /// Records an enum.
    ///
    /// - Parameter node: The enum.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, name: node.name.text, kind: .enum)
    }

    /// Records an actor, as a concrete type that can't be subclassed.
    ///
    /// - Parameter node: The actor.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, name: node.name.text, kind: .other)
    }

    /// Records a protocol, skipping its requirements, which have no bodies.
    ///
    /// - Parameter node: The protocol.
    /// - Returns: `.skipChildren`.
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let members = SwiftMembers.members(of: node)
        types.append(TypeFact(name: node.name.text, line: line(node), kind: .protocol, members: members))
        return .skipChildren
    }

    /// Records an extension that adds conformances, and enters it so its initializers are named for the type.
    ///
    /// - Parameter node: The extension.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = FactText.typeName(node.extendedType.trimmedDescription)
        if node.inheritanceClause != nil {
            let members = SwiftMembers.members(of: node)
            types.append(TypeFact(name: name, line: line(node), kind: .extension, members: members))
        }
        enclosingTypes.append(name)
        return .visitChildren
    }

    /// Leaves a class.
    ///
    /// - Parameter node: The class.
    override func visitPost(_ node: ClassDeclSyntax) { enclosingTypes.removeLast() }

    /// Leaves a struct.
    ///
    /// - Parameter node: The struct.
    override func visitPost(_ node: StructDeclSyntax) { enclosingTypes.removeLast() }

    /// Leaves an enum.
    ///
    /// - Parameter node: The enum.
    override func visitPost(_ node: EnumDeclSyntax) { enclosingTypes.removeLast() }

    /// Leaves an actor.
    ///
    /// - Parameter node: The actor.
    override func visitPost(_ node: ActorDeclSyntax) { enclosingTypes.removeLast() }

    /// Leaves an extension.
    ///
    /// - Parameter node: The extension.
    override func visitPost(_ node: ExtensionDeclSyntax) { enclosingTypes.removeLast() }

    /// Records a function with a body.
    ///
    /// - Parameter node: The function.
    /// - Returns: `.visitChildren`, for the `switch` statements inside it.
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.body != nil else { return .visitChildren }
        let parameters = SwiftMembers.parameters(node.signature.parameterClause)
        let returns = node.signature.returnClause?.type.trimmedDescription
        functions.append(FunctionFact(
            name: node.name.text, line: line(node), parameters: parameters, owner: enclosingTypes.last, returns: returns
        ))
        return .visitChildren
    }

    /// Records an initializer with a body, as `<Type>.init`.
    ///
    /// - Parameter node: The initializer.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.body != nil else { return .visitChildren }
        let name = (enclosingTypes.last ?? "") + ".init"
        let parameters = SwiftMembers.parameters(node.signature.parameterClause)
        functions.append(FunctionFact(name: name, line: line(node), parameters: parameters))
        return .visitChildren
    }

    /// Records a `switch` statement's subject.
    ///
    /// - Parameter node: The `switch`.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        if let subject = FactText.subject(node.subject.trimmedDescription) {
            let labels = node.cases.compactMap { $0.as(SwitchCaseSyntax.self)?.label.as(SwitchCaseLabelSyntax.self) }
            let cases = labels.flatMap(\.caseItems).compactMap { FactText.caseLabel($0.pattern.trimmedDescription) }
            switches.append(SwitchFact(subject: subject, line: line(node), cases: cases))
        }
        return .visitChildren
    }

    /// Records a type declaration and enters it.
    ///
    /// - Parameters:
    ///   - node: The declaration.
    ///   - name: Its name.
    ///   - kind: Its kind.
    /// - Returns: `.visitChildren`.
    private func enter(_ node: some DeclGroupSyntax, name: String, kind: TypeKind) -> SyntaxVisitorContinueKind {
        types.append(TypeFact(name: name, line: line(node), kind: kind, members: SwiftMembers.members(of: node)))
        enclosingTypes.append(name)
        return .visitChildren
    }

    /// Converts a node's position to a line.
    ///
    /// - Parameter node: The node.
    /// - Returns: Its 1-indexed line.
    private func line(_ node: some SyntaxProtocol) -> Int {
        converter.location(for: node.positionAfterSkippingLeadingTrivia).line
    }
}

/// Reads a Swift type's members and a function's parameters for the structure facts.
enum SwiftMembers {
    private static let traps: Set<String> = ["fatalError", "preconditionFailure", "abort", "Swift.fatalError"]

    /// Reads a type's supertypes, stored properties, and methods (a protocol's method requirements).
    ///
    /// - Parameter node: The type declaration.
    /// - Returns: Its members.
    static func members(of node: some DeclGroupSyntax) -> TypeMembers {
        var members = TypeMembers(supertypes: Self.supertypes(of: node))
        for item in node.memberBlock.members {
            if let variable = item.decl.as(VariableDeclSyntax.self) { members.fields += Self.fields(of: variable) }
            if let function = item.decl.as(FunctionDeclSyntax.self) { Self.addMethod(function, to: &members) }
        }
        return members
    }

    /// Adds a method, noting whether it overrides and whether its body is empty, only traps, or opens with a
    /// precondition.
    ///
    /// - Parameters:
    ///   - function: The method.
    ///   - members: The type's members so far.
    static func addMethod(_ function: FunctionDeclSyntax, to members: inout TypeMembers) {
        let name = function.name.text
        members.methods.append(name)
        guard let statements = function.body?.statements else { return }
        let isOverride = function.modifiers.contains { $0.name.tokenKind == .keyword(.override) }
        if isOverride { members.overrides.append(name) }
        classify(statements, of: name, isOverride: isOverride, into: &members)
        if isGuarded(function, statements) { members.guarded.append(name) }
    }

    /// Reports whether a method opens with a precondition on its arguments before more code.
    ///
    /// - Parameters:
    ///   - function: The method.
    ///   - statements: Its body.
    /// - Returns: Whether its first statement narrows what it accepts.
    private static func isGuarded(_ function: FunctionDeclSyntax, _ statements: CodeBlockItemListSyntax) -> Bool {
        let arguments = Set(parameters(function.signature.parameterClause).map { String($0.prefix { $0 != ":" }) })
        guard statements.count > 1, let first = statements.first else { return false }
        return isPrecondition(first, on: arguments)
    }

    /// Notes a method whose body is empty or does nothing but refuse: an `override` that throws or traps, or
    /// another method that traps or throws an error named for an unsupported operation.
    ///
    /// - Parameters:
    ///   - statements: The method's body.
    ///   - name: The method's name.
    ///   - isOverride: Whether it's an `override`.
    ///   - members: The type's members so far.
    private static func classify(
        _ statements: CodeBlockItemListSyntax, of name: String, isOverride: Bool, into members: inout TypeMembers
    ) {
        let only = statements.count == 1 ? statements.first : nil
        if statements.isEmpty { isOverride ? members.empty.append(name) : members.emptyOwn.append(name) }
        if isOverride, only.map(isTrap) == true { members.refused.append(name) }
        if !isOverride, only.map(isUnsupported) == true { members.refusedOwn.append(name) }
    }

    /// Reports whether a statement refuses an operation: a trap, or a `throw` whose error says the operation
    /// is unsupported or unimplemented. Other throws are ordinary failures of a throwing method.
    ///
    /// - Parameter statement: The body's only statement.
    /// - Returns: Whether it refuses.
    private static func isUnsupported(_ statement: CodeBlockItemSyntax) -> Bool {
        guard statement.item.is(ThrowStmtSyntax.self) else { return isTrap(statement) }
        return FactText.saysUnsupported(statement.trimmedDescription)
    }

    /// Reports whether a statement is a precondition on the arguments that traps or throws:
    /// `precondition(…)`, or a `guard` whose `else` ends by trapping or throwing, testing a parameter.
    ///
    /// - Parameters:
    ///   - statement: A body's first statement.
    ///   - arguments: The method's parameter names.
    /// - Returns: Whether it narrows what the method accepts.
    private static func isPrecondition(_ statement: CodeBlockItemSyntax, on arguments: Set<String>) -> Bool {
        if let call = statement.item.as(FunctionCallExprSyntax.self),
           call.calledExpression.trimmedDescription == "precondition" {
            return FactText.mentions(call.arguments.first?.trimmedDescription ?? "", anyOf: arguments)
        }
        guard let check = statement.item.as(GuardStmtSyntax.self), check.body.statements.last.map(isTrap) == true
        else { return false }
        return FactText.mentions(check.conditions.trimmedDescription, anyOf: arguments)
    }

    /// Reports whether a statement only throws or traps.
    ///
    /// - Parameter statement: The statement.
    /// - Returns: Whether it's a `throw` or a call to `fatalError`, `preconditionFailure`, or `abort`.
    private static func isTrap(_ statement: CodeBlockItemSyntax) -> Bool {
        if statement.item.is(ThrowStmtSyntax.self) { return true }
        let call = statement.item.as(FunctionCallExprSyntax.self)
        return call.map { traps.contains($0.calledExpression.trimmedDescription) } ?? false
    }

    /// Lists the stored instance properties one declaration introduces.
    ///
    /// - Parameter variable: The `let`/`var` declaration.
    /// - Returns: Each stored property as `name:Type` or `name`; none for a static or computed property.
    static func fields(of variable: VariableDeclSyntax) -> [String] {
        let isStatic = variable.modifiers.contains {
            [.keyword(.static), .keyword(.class)].contains($0.name.tokenKind)
        }
        guard !isStatic else { return [] }
        return variable.bindings.compactMap { binding in
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  isStored(binding) else { return nil }
            return FactText.member(name, type: binding.typeAnnotation?.type.trimmedDescription)
        }
    }

    /// Reports whether a binding stores a value: no accessors, or only `willSet`/`didSet` observers.
    ///
    /// - Parameter binding: The binding.
    /// - Returns: Whether it's a stored property.
    private static func isStored(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessors = binding.accessorBlock?.accessors else { return true }
        guard let list = accessors.as(AccessorDeclListSyntax.self) else { return false }
        return list.allSatisfy { ["willSet", "didSet"].contains($0.accessorSpecifier.text) }
    }

    /// Lists a type's inherited types by bare name.
    ///
    /// - Parameter node: The type or extension.
    /// - Returns: Its superclass (first, if any), protocols, and constraints.
    static func supertypes(of node: some DeclGroupSyntax) -> [String] {
        (node.inheritanceClause?.inheritedTypes ?? []).map { FactText.typeName($0.type.trimmedDescription) }
    }

    /// Lists a function's named parameters.
    ///
    /// - Parameter clause: The parameter clause.
    /// - Returns: Each parameter as `name:Type`, by its internal name and without `inout` or attributes;
    ///   `_` names are left out.
    static func parameters(_ clause: FunctionParameterClauseSyntax) -> [String] {
        clause.parameters.compactMap { parameter in
            let name = (parameter.secondName ?? parameter.firstName).text
            let type = parameter.type.as(AttributedTypeSyntax.self)?.baseType ?? parameter.type
            return name == "_" ? nil : FactText.member(name, type: type.trimmedDescription)
        }
    }
}
