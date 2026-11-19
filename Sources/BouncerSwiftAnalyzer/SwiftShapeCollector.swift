import SwiftSyntax
import BouncerCore
import BouncerRules

/// Walks a Swift file collecting the size rules' facts: every type's extent, every closure, long
/// boolean chains, generic parameter counts, and what else shares the file scope with its types.
final class SwiftShapeCollector: SyntaxVisitor {
    /// Callees whose closure argument is a test-suite block, such as Quick's `describe { … }`.
    static let suiteCallees: Set<String> = [
        "describe", "context", "it", "fdescribe", "fcontext", "fit", "xdescribe", "xcontext", "xit",
        "beforeEach", "afterEach", "beforeSuite", "afterSuite", "aroundEach"
    ]
    private(set) var markers: [CollectedMarker] = []
    private var types: [DeclaredType] = []
    private var closures: [CollectedClosure] = []
    private var topLevelOthers: [String] = []
    private let converter: SourceLocationConverter

    /// Creates a collector for a parsed file.
    ///
    /// - Parameter converter: Converts syntax positions to line numbers.
    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    /// Assembles the collected facts. Call after visiting the whole tree.
    ///
    /// - Parameter typedNames: The file's variables, properties, and parameters, from `SwiftNameCollector`.
    /// - Returns: The file's shape facts.
    func facts(typedNames: [CollectedName]) -> ShapeFacts {
        ShapeFacts(types: types, closures: closures, typedNames: typedNames, topLevelOthers: topLevelOthers)
    }

    /// Records a class's extent.
    ///
    /// - Parameter node: The class declaration.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        recordType(node.name.text, node)
    }

    /// Records a struct's extent.
    ///
    /// - Parameter node: The struct declaration.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordType(node.name.text, node)
    }

    /// Records an enum's extent.
    ///
    /// - Parameter node: The enum declaration.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        recordType(node.name.text, node)
    }

    /// Records an actor's extent.
    ///
    /// - Parameter node: The actor declaration.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        recordType(node.name.text, node)
    }

    /// Records a protocol's extent.
    ///
    /// - Parameter node: The protocol declaration.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        recordType(node.name.text, node)
    }

    /// Records a visible top-level extension's extended type, which shares the file with its types.
    ///
    /// - Parameter node: The extension declaration.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let base = node.extendedType.trimmedDescription.split(whereSeparator: { ".<".contains($0) }).first
        return recordTopLevelOther(base.map(String.init) ?? "", node)
    }

    /// Records a visible top-level function, which means the file isn't only about its types.
    ///
    /// - Parameter node: The function declaration.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTopLevelOther(node.name.text, node)
    }

    /// Records a visible top-level variable, which means the file isn't only about its types.
    ///
    /// - Parameter node: The variable declaration.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTopLevelOther(node.bindings.first?.pattern.trimmedDescription ?? "", node)
    }

    /// Records a closure's extent, unless it's a property initializer (`= { … }()`), a test-suite
    /// block, or a result-builder body passed to a type, such as `VStack { … }`.
    ///
    /// - Parameter node: The closure.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        guard !isInitializer(node), !isSuiteOrBuilderBlock(node) else { return .visitChildren }
        let end = converter.location(for: node.endPositionBeforeTrailingTrivia).line
        closures.append(CollectedClosure(startLine: line(of: node), endLine: end))
        return .visitChildren
    }

    /// Records a generic parameter clause's size at its declaration's line.
    ///
    /// - Parameter node: The generic parameter clause.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: GenericParameterClauseSyntax) -> SyntaxVisitorContinueKind {
        let declaration = node.parent.map { line(of: $0) } ?? line(of: node)
        let count = node.parameters.count
        markers.append(CollectedMarker(kind: .tooManyGenericParameters, line: declaration, value: count))
        return .visitChildren
    }

    /// Records the outermost `&&`/`||` chain in an operator sequence, with its operand count.
    ///
    /// - Parameter node: The operator sequence.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        guard Self.logicalOperatorCount(node) > 0, !isNestedOperand(node), !isInEqualityOperator(node) else {
            return .visitChildren
        }
        markers.append(CollectedMarker(kind: .longBooleanExpression, line: line(of: node), value: operands(of: node)))
        return .visitChildren
    }

    /// Records a type declaration's extent, nesting, and visibility.
    ///
    /// - Parameters:
    ///   - name: The type's name.
    ///   - node: The declaration.
    /// - Returns: `.visitChildren`.
    private func recordType(_ name: String, _ node: some DeclGroupSyntax) -> SyntaxVisitorContinueKind {
        let end = converter.location(for: node.memberBlock.endPositionBeforeTrailingTrivia).line
        types.append(DeclaredType(
            name: name, startLine: line(of: node), endLine: end, isTopLevel: isTopLevel(node),
            visibility: SwiftDeclarationSummaryBuilder.visibility(of: node.modifiers)
        ))
        return .visitChildren
    }

    /// Records a non-type, non-private declaration at file scope.
    ///
    /// - Parameters:
    ///   - name: The declared name, or the extended type's name.
    ///   - node: The declaration.
    /// - Returns: `.visitChildren`.
    private func recordTopLevelOther(_ name: String, _ node: some WithModifiersSyntax) -> SyntaxVisitorContinueKind {
        let isPrivate = SwiftDeclarationSummaryBuilder.visibility(of: node.modifiers) == .private
        if isTopLevel(node), !isPrivate { topLevelOthers.append(name) }
        return .visitChildren
    }

    /// Counts the operands of an operator sequence's `&&`/`||` chain, including those inside
    /// parenthesized or negated sub-chains such as `a && !(b || c)`.
    ///
    /// - Parameter node: The operator sequence.
    /// - Returns: The number of leaf conditions.
    private func operands(of node: SequenceExprSyntax) -> Int {
        let nested = node.elements.compactMap(Self.parenthesizedChain).map { operands(of: $0) - 1 }
        return Self.logicalOperatorCount(node) + 1 + nested.reduce(0, +)
    }

    /// Counts the `&&` and `||` operators directly in an operator sequence.
    ///
    /// - Parameter node: The operator sequence.
    /// - Returns: The number of logical operators.
    private static func logicalOperatorCount(_ node: SequenceExprSyntax) -> Int {
        node.elements.filter {
            let text = $0.as(BinaryOperatorExprSyntax.self)?.operator.text
            return text == "&&" || text == "||"
        }.count
    }

    /// Finds the logical chain inside a parenthesized, possibly negated, operand: `(a || b)` or `!(a || b)`.
    ///
    /// - Parameter element: One element of an operator sequence.
    /// - Returns: The inner sequence, if the element wraps one that has `&&`/`||`.
    private static func parenthesizedChain(_ element: ExprSyntax) -> SequenceExprSyntax? {
        let operand = element.as(PrefixOperatorExprSyntax.self)?.expression ?? element
        guard let tuple = operand.as(TupleExprSyntax.self), tuple.elements.count == 1,
              let inner = tuple.elements.first?.expression.as(SequenceExprSyntax.self) else { return nil }
        return logicalOperatorCount(inner) > 0 ? inner : nil
    }

    /// Reports whether a sequence is a parenthesized operand of an enclosing chain, which counts it.
    ///
    /// - Parameter node: The operator sequence.
    /// - Returns: Whether an enclosing `&&`/`||` sequence already includes its operands.
    private func isNestedOperand(_ node: SequenceExprSyntax) -> Bool {
        guard let tuple = node.parent?.parent?.parent?.as(TupleExprSyntax.self) else { return false }
        let wrapper = tuple.parent?.is(PrefixOperatorExprSyntax.self) == true ? tuple.parent : Syntax(tuple)
        guard let outer = wrapper?.parent?.as(ExprListSyntax.self)?.parent?.as(SequenceExprSyntax.self) else {
            return false
        }
        return Self.logicalOperatorCount(outer) > 0
    }

    /// Reports whether a closure initializes a property, as in `let x = { … }` or `lazy var x = { … }()`.
    ///
    /// - Parameter node: The closure.
    /// - Returns: Whether it's the value, or the immediately called value, of an initializer.
    private func isInitializer(_ node: ClosureExprSyntax) -> Bool {
        let call = node.parent?.as(FunctionCallExprSyntax.self)
        let value = call?.calledExpression.id == node.id ? call.map(Syntax.init) : Syntax(node)
        return value?.parent?.is(InitializerClauseSyntax.self) ?? false
    }

    /// Reports whether a closure is passed to a test-suite call such as `describe`, or to a type's
    /// initializer, which in Swift is almost always a result-builder body such as `Section { … }`.
    ///
    /// - Parameter node: The closure.
    /// - Returns: Whether the call it's an argument or trailing closure of is a suite callee or a type.
    private func isSuiteOrBuilderBlock(_ node: ClosureExprSyntax) -> Bool {
        let call = node.parent?.as(FunctionCallExprSyntax.self)
            ?? node.parent?.parent?.parent?.as(FunctionCallExprSyntax.self)
        let callee = call?.calledExpression.trimmedDescription.split(separator: ".").last.map(String.init) ?? ""
        return Self.suiteCallees.contains(callee) || callee.first?.isUppercase == true
    }

    /// Reports whether a node sits inside an `==` implementation, whose field-by-field `&&` chain
    /// is the idiom rather than a smell.
    ///
    /// - Parameter node: The node.
    /// - Returns: Whether an enclosing function is named `==`.
    private func isInEqualityOperator(_ node: some SyntaxProtocol) -> Bool {
        var current = node.parent
        while let parent = current {
            if parent.as(FunctionDeclSyntax.self)?.name.text == "==" { return true }
            current = parent.parent
        }
        return false
    }

    /// Reports whether a declaration sits directly at file scope.
    ///
    /// - Parameter node: The declaration.
    /// - Returns: Whether its statement's list is the source file's.
    private func isTopLevel(_ node: some SyntaxProtocol) -> Bool {
        node.parent?.parent?.parent?.is(SourceFileSyntax.self) ?? false
    }

    /// Converts a node's position to its 1-indexed line.
    ///
    /// - Parameter node: The node.
    /// - Returns: Its line.
    private func line(of node: some SyntaxProtocol) -> Int {
        converter.location(for: node.positionAfterSkippingLeadingTrivia).line
    }
}
