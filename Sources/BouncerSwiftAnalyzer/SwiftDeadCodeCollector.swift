import SwiftSyntax
import BouncerCore
import BouncerRules

/// Finds Swift declarations nothing else in the file uses, for the dead-code rules.
///
/// A `private`/`fileprivate` function, property, or type is unused when its name appears nowhere outside
/// its own declaration. Members of a type that declares a conformance anywhere in the file are skipped,
/// since they may be protocol witnesses, as are overrides, `@objc` and Interface Builder hooks, attributed
/// properties (property wrappers), stored class properties (often held only to keep an object alive),
/// `_`-prefixed names, and names the compiler calls implicitly, such as a result builder's `buildBlock`.
final class SwiftDeadCodeCollector: SyntaxVisitor {
    /// A declaration that may be unused, with the extent its own name doesn't count as a use inside.
    private struct Candidate {
        let declaration: UnusedDeclaration
        let extent: Range<AbsolutePosition>
        let container: String?
    }

    /// An enclosing type or extension.
    private struct Container {
        let name: String
        let defaultsToPrivate: Bool
        let isReferenceType: Bool
    }

    private let converter: SourceLocationConverter
    private var containers: [Container] = []
    private var exemptContainers: Set<String> = []
    private var candidates: [Candidate] = []

    /// Creates a dead-code collector for a parsed file.
    ///
    /// - Parameter converter: Converts syntax positions to line numbers.
    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    /// Lists the collected declarations nothing uses. Call after visiting the whole tree.
    ///
    /// - Parameter uses: Where each name is used in the file, from `SwiftUseCollector`.
    /// - Returns: The unused declarations, in source order.
    func unused(uses: [String: [AbsolutePosition]]) -> [UnusedDeclaration] {
        candidates.filter { candidate in
            if let container = candidate.container, exemptContainers.contains(container) { return false }
            guard candidate.declaration.kind == .privateSymbol else { return true }
            return !(uses[candidate.declaration.name] ?? []).contains { !candidate.extent.contains($0) }
        }.map(\.declaration)
    }

    /// Records a private function and its unused parameters.
    ///
    /// - Parameter node: The function.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        recordIfPrivate(node.name.text, "Private function", node)
        recordParameters(of: node.name.text, node, signature: node.signature, body: node.body)
        return .visitChildren
    }

    /// Records an initializer's unused parameters.
    ///
    /// - Parameter node: The initializer.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        recordParameters(of: "init", node, signature: node.signature, body: node.body)
        return .visitChildren
    }

    /// Records each private name a `let`/`var` declares, skipping attributed and stored class properties.
    ///
    /// - Parameter node: The variable declaration.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.attributes.isEmpty else { return .visitChildren }
        let isStatic = node.modifiers.contains { [.keyword(.static), .keyword(.class)].contains($0.name.tokenKind) }
        let skipsStored = !isStatic && containers.last?.isReferenceType == true
        for binding in node.bindings where !(skipsStored && isStored(binding)) {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
            recordIfPrivate(name, "Private property", node)
        }
        return .visitChildren
    }

    /// Records a private class, then enters it.
    ///
    /// - Parameter node: The class.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(node.name.text, node, inheritance: node.inheritanceClause)
    }

    /// Records a private actor, then enters it.
    ///
    /// - Parameter node: The actor.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(node.name.text, node, inheritance: node.inheritanceClause)
    }

    /// Records a private struct, then enters it.
    ///
    /// - Parameter node: The struct.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(node.name.text, node, inheritance: node.inheritanceClause)
    }

    /// Records a private enum, then enters it.
    ///
    /// - Parameter node: The enum.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(node.name.text, node, inheritance: node.inheritanceClause)
    }

    /// Leaves a type or extension, once past its members; a protocol's are never entered.
    ///
    /// - Parameter node: The member block of the type or extension being left.
    override func visitPost(_ node: MemberBlockSyntax) { containers.removeLast() }

    /// Records a private protocol, and exempts its extensions' members, which may be default witnesses.
    ///
    /// - Parameter node: The protocol.
    /// - Returns: `.skipChildren`, since its requirements are satisfied rather than called by name here.
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        recordIfPrivate(node.name.text, "Private protocol", node)
        exemptContainers.insert(node.name.text)
        return .skipChildren
    }

    /// Records a private type alias.
    ///
    /// - Parameter node: The type alias.
    /// - Returns: `.skipChildren`.
    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        recordIfPrivate(node.name.text, "Private type alias", node)
        return .skipChildren
    }

    /// Enters an extension, whose members default to private in a `private extension`.
    ///
    /// - Parameter node: The extension.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = Self.simpleName(of: node.extendedType)
        if node.inheritanceClause != nil || Self.hasExemptAttribute(node.attributes) { exemptContainers.insert(name) }
        let defaultsToPrivate = Self.isPrivateAccess(node.modifiers)
        containers.append(Container(name: name, defaultsToPrivate: defaultsToPrivate, isReferenceType: false))
        return .visitChildren
    }

    /// Records a type if private, notes whether its members may be witnesses, and enters it.
    ///
    /// - Parameters:
    ///   - name: The type's name.
    ///   - node: The declaration.
    ///   - inheritance: Its superclass and conformances, if any.
    /// - Returns: `.visitChildren`.
    private func enterType(
        _ name: String, _ node: some DeclSyntaxProtocol & WithModifiersSyntax & WithAttributesSyntax,
        inheritance: InheritanceClauseSyntax?
    ) -> SyntaxVisitorContinueKind {
        recordIfPrivate(name, "Private type", node)
        if inheritance != nil || Self.hasExemptAttribute(node.attributes) { exemptContainers.insert(name) }
        let isReferenceType = node.is(ClassDeclSyntax.self) || node.is(ActorDeclSyntax.self)
        containers.append(Container(name: name, defaultsToPrivate: false, isReferenceType: isReferenceType))
        return .visitChildren
    }

    /// Records a declaration as a candidate if it's private and nothing outside the code calls it.
    ///
    /// - Parameters:
    ///   - name: The declared name.
    ///   - detail: What it is, such as `"Private function"`.
    ///   - node: The declaration, for its modifiers, attributes, line, and extent.
    private func recordIfPrivate(
        _ name: String, _ detail: String, _ node: some WithModifiersSyntax & WithAttributesSyntax
    ) {
        guard isPrivate(node.modifiers) else { return }
        guard !Self.isExempt(name, modifiers: node.modifiers, attributes: node.attributes) else { return }
        let line = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        let declaration = UnusedDeclaration(kind: .privateSymbol, name: name, line: line, detail: detail)
        candidates.append(Candidate(declaration: declaration, extent: node.position..<node.endPosition,
                                    container: containers.last?.name))
    }

    /// Records each parameter a function's body never uses, unless the signature is fixed from outside.
    ///
    /// - Parameters:
    ///   - owner: The function's name.
    ///   - node: The function or initializer.
    ///   - signature: Its signature.
    ///   - body: Its body, or `nil` for a requirement.
    private func recordParameters(
        of owner: String, _ node: some WithModifiersSyntax & WithAttributesSyntax,
        signature: FunctionSignatureSyntax, body: CodeBlockSyntax?
    ) {
        guard let body, !Self.isStub(body) else { return }
        guard !Self.isExempt(owner, modifiers: node.modifiers, attributes: node.attributes) else { return }
        let used = SwiftUseCollector.names(in: body)
        for parameter in signature.parameterClause.parameters {
            let name = (parameter.secondName ?? parameter.firstName).text
            guard !name.hasPrefix("_"), !used.contains(name) else { continue }
            recordParameter(name, parameter, owner: owner)
        }
    }

    /// Records one unused parameter as a candidate, reported unless its container is exempt.
    ///
    /// - Parameters:
    ///   - name: The parameter's internal name.
    ///   - parameter: The parameter, for its line and extent.
    ///   - owner: The function's name.
    private func recordParameter(_ name: String, _ parameter: FunctionParameterSyntax, owner: String) {
        let line = converter.location(for: parameter.positionAfterSkippingLeadingTrivia).line
        let declaration = UnusedDeclaration(kind: .parameter, name: name, line: line, detail: owner)
        let extent = parameter.position..<parameter.endPosition
        candidates.append(Candidate(declaration: declaration, extent: extent, container: containers.last?.name))
    }

    /// Reports whether a declaration is private, by its own modifier or a `private extension`'s default.
    ///
    /// - Parameter modifiers: The declaration's modifiers.
    /// - Returns: Whether it's visible only within the file.
    private func isPrivate(_ modifiers: DeclModifierListSyntax) -> Bool {
        if Self.isPrivateAccess(modifiers) { return true }
        let hasAccess = modifiers.contains { Self.accessKeywords.contains($0.name.tokenKind) }
        return containers.last?.defaultsToPrivate == true && !hasAccess
    }

    /// Reports whether a binding is stored rather than computed; observers don't make it computed.
    ///
    /// - Parameter binding: The pattern binding.
    /// - Returns: Whether it has storage.
    private func isStored(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessors = binding.accessorBlock?.accessors else { return true }
        guard let list = accessors.as(AccessorDeclListSyntax.self) else { return false }
        return list.allSatisfy { [.keyword(.willSet), .keyword(.didSet)].contains($0.accessorSpecifier.tokenKind) }
    }
}
