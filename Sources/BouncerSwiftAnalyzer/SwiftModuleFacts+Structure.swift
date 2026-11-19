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

    /// The collected facts.
    var structure: StructureFacts {
        StructureFacts(types: types, functions: functions, switches: switches, isGenerated: isGenerated)
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
            let supertypes = TypeMembers(supertypes: SwiftMembers.supertypes(of: node))
            types.append(TypeFact(name: name, line: line(node), kind: .extension, members: supertypes))
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
        functions.append(FunctionFact(name: node.name.text, line: line(node), parameters: parameters))
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

    /// Reads a type's supertypes, stored properties, and methods.
    ///
    /// - Parameter node: The type declaration.
    /// - Returns: Its members; methods only for a class.
    static func members(of node: some DeclGroupSyntax) -> TypeMembers {
        var members = TypeMembers(supertypes: Self.supertypes(of: node))
        for item in node.memberBlock.members {
            if let variable = item.decl.as(VariableDeclSyntax.self) { members.fields += Self.fields(of: variable) }
            if node.is(ClassDeclSyntax.self), let function = item.decl.as(FunctionDeclSyntax.self) {
                Self.addMethod(function, to: &members)
            }
        }
        return members
    }

    /// Adds a class method, noting an `override` whose body is empty or only traps.
    ///
    /// - Parameters:
    ///   - function: The method.
    ///   - members: The class's members so far.
    static func addMethod(_ function: FunctionDeclSyntax, to members: inout TypeMembers) {
        let name = function.name.text
        members.methods.append(name)
        guard function.modifiers.contains(where: { $0.name.tokenKind == .keyword(.override) }),
              let statements = function.body?.statements else { return }
        if statements.isEmpty { members.empty.append(name) }
        if statements.count == 1, let only = statements.first, isTrap(only) { members.refused.append(name) }
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
