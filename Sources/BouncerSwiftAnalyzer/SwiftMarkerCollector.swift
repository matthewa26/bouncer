import SwiftSyntax
import BouncerRules

/// Walks a whole Swift file once, recording each single-location smell as a `CollectedMarker`.
final class SwiftMarkerCollector: SyntaxVisitor {
    private static let allowedNumbers: Set<String> = ["0", "1", "2", "0.0", "1.0"]
    private(set) var markers: [CollectedMarker] = []
    private let converter: SourceLocationConverter

    /// Creates a marker collector for a parsed file.
    ///
    /// - Parameter converter: Converts syntax positions to line numbers.
    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    /// Records a force unwrap.
    ///
    /// - Parameter node: The force-unwrap expression.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
        record(.forceUnwrap, at: node)
    }

    /// Records a `try!`, ignoring plain `try` and `try?`.
    ///
    /// - Parameter node: The try expression.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.questionOrExclamationMark?.tokenKind == .exclamationMark else { return .visitChildren }
        return record(.forceTry, at: node)
    }

    /// Records an `as!`, ignoring plain `as` and `as?`.
    ///
    /// - Parameter node: The unfolded cast expression.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: UnresolvedAsExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.questionOrExclamationMark?.tokenKind == .exclamationMark else { return .visitChildren }
        return record(.forceCast, at: node)
    }

    /// Records an implicitly unwrapped optional type, such as `String!`.
    ///
    /// - Parameter node: The type.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ImplicitlyUnwrappedOptionalTypeSyntax) -> SyntaxVisitorContinueKind {
        record(.implicitlyUnwrappedOptional, at: node)
    }

    /// Records a `catch` whose body has no statements and no explanatory comment.
    ///
    /// - Parameter node: The catch clause.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        let body = node.body
        let hasComment = body.leftBrace.trailingTrivia.hasComment || body.rightBrace.leadingTrivia.hasComment
        guard body.statements.isEmpty, !hasComment else { return .visitChildren }
        return record(.emptyCatch, at: node)
    }

    /// Records the first statement after a `return`, `throw`, `break`, `continue`, or `fallthrough`.
    ///
    /// - Parameter node: A block's statement list.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: CodeBlockItemListSyntax) -> SyntaxVisitorContinueKind {
        let items = Array(node)
        guard let jump = items.firstIndex(where: { isJump($0.item) }), jump + 1 < items.count else {
            return .visitChildren
        }
        return record(.unreachableCode, at: items[jump + 1])
    }

    /// Records a ternary whose operator sequence, or an enclosing one, holds another ternary.
    ///
    /// - Parameter node: The operator sequence.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let ternaries = node.elements.filter { $0.is(UnresolvedTernaryExprSyntax.self) }
        guard let first = ternaries.first else { return .visitChildren }
        guard ternaries.count > 1 || hasTernaryAncestor(node) else { return .visitChildren }
        return record(.nestedTernary, at: first)
    }

    /// Records an `else` whose `if` branch always exits, so the `else` only adds nesting.
    ///
    /// - Parameter node: The `if` expression.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        guard let elseKeyword = node.elseKeyword, let last = node.body.statements.last, isJump(last.item) else {
            return .visitChildren
        }
        return record(.elseAfterReturn, at: elseKeyword)
    }

    /// Records a stored top-level or `static` `var`: state any code can change. Computed properties hold none.
    ///
    /// - Parameter node: The variable declaration.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.bindingSpecifier.tokenKind == .keyword(.var),
              node.bindings.contains(where: { $0.accessorBlock == nil }) else { return .visitChildren }
        let isStatic = node.modifiers.contains { [.keyword(.static), .keyword(.class)].contains($0.name.tokenKind) }
        let isTopLevel = node.parent?.parent?.parent?.is(SourceFileSyntax.self) ?? false
        return isStatic || isTopLevel ? record(.globalMutableState, at: node) : .visitChildren
    }

    /// Records the length of each outermost chain of calls, such as `a.b().c().d()`.
    ///
    /// - Parameter node: A call.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard !(node.parent?.is(MemberAccessExprSyntax.self) ?? false) else { return .visitChildren }
        let length = chainLength(from: ExprSyntax(node))
        guard length > 1 else { return .visitChildren }
        markers.append(CollectedMarker(kind: .longMessageChain, line: line(of: node), value: length))
        return .visitChildren
    }

    /// Records a test method that never asserts anything.
    ///
    /// - Parameter node: The function declaration.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body, isTest(node), !SwiftAssertionFinder.containsAssertion(body) else {
            return .visitChildren
        }
        return record(.testWithoutAssertions, at: node.name)
    }

    /// Records an integer literal that isn't given a name.
    ///
    /// - Parameter node: The literal.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: IntegerLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        recordIfMagic(node, text: node.literal.text)
    }

    /// Records a floating-point literal that isn't given a name.
    ///
    /// - Parameter node: The literal.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: FloatLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        recordIfMagic(node, text: node.literal.text)
    }

    /// Counts the calls in a chain, following each call's receiver back through member access.
    ///
    /// - Parameter expression: The outermost call.
    /// - Returns: How many calls the chain holds.
    private func chainLength(from expression: ExprSyntax) -> Int {
        var current: ExprSyntax? = expression, count = 0
        while let node = current {
            let unwrapped = node.as(OptionalChainingExprSyntax.self)?.expression ?? node
            guard let call = unwrapped.as(FunctionCallExprSyntax.self) else { break }
            count += 1
            current = call.calledExpression.as(MemberAccessExprSyntax.self)?.base
        }
        return count
    }

    /// Reports whether a function is a test: an XCTest-style `test…` method or a swift-testing `@Test`.
    ///
    /// - Parameter node: The function declaration.
    /// - Returns: Whether it's a test.
    private func isTest(_ node: FunctionDeclSyntax) -> Bool {
        let hasTestAttribute = node.attributes.contains {
            $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Test"
        }
        let isXCTestMethod = node.name.text.hasPrefix("test") && node.signature.parameterClause.parameters.isEmpty
        return hasTestAttribute || isXCTestMethod
    }

    /// Converts a node's position to its 1-indexed line.
    ///
    /// - Parameter node: The node.
    /// - Returns: Its line.
    private func line(of node: some SyntaxProtocol) -> Int {
        converter.location(for: node.positionAfterSkippingLeadingTrivia).line
    }

    /// Records a marker at a node's first non-trivia position.
    ///
    /// - Parameters:
    ///   - kind: The smell to record.
    ///   - node: Where it occurs.
    /// - Returns: `.visitChildren`, so visitor overrides can return it directly.
    private func record(_ kind: MarkerKind, at node: some SyntaxProtocol) -> SyntaxVisitorContinueKind {
        let line = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        markers.append(CollectedMarker(kind: kind, line: line))
        return .visitChildren
    }

    /// Records a numeric literal as magic unless it's trivially small or something names it.
    ///
    /// - Parameters:
    ///   - node: The literal.
    ///   - text: The literal's source text.
    /// - Returns: `.visitChildren`.
    private func recordIfMagic(_ node: some ExprSyntaxProtocol, text: String) -> SyntaxVisitorContinueKind {
        guard !Self.allowedNumbers.contains(text), !isNamed(Syntax(node)) else { return .visitChildren }
        return record(.magicNumber, at: node)
    }

    /// Walks up through arithmetic and grouping to see whether a literal is bound to a name.
    ///
    /// A `let`/`var` or default-argument initializer, an enum raw value, a dictionary entry, a
    /// labeled argument such as `default: 40`, or a `case` pattern all name the number they hold,
    /// including through a call such as `["maxLines": .int(10)]`.
    ///
    /// - Parameter node: The literal.
    /// - Returns: Whether an enclosing construct names it.
    private func isNamed(_ node: Syntax) -> Bool {
        var current = node.parent
        while let parent = current {
            if Self.namingNodes.contains(where: { parent.is($0) }) { return true }
            if let labeled = parent.as(LabeledExprSyntax.self), labeled.label != nil { return true }
            guard isTransparent(parent) else { return false }
            current = parent.parent
        }
        return false
    }

    /// Reports whether a node merely combines or groups its operands, so a name above it still applies.
    ///
    /// - Parameter node: The node to check.
    /// - Returns: Whether it's arithmetic, a prefix operator, a parenthesis, or a call's argument list.
    private func isTransparent(_ node: Syntax) -> Bool {
        Self.transparentNodes.contains { node.is($0) }
    }

    private static let namingNodes: [SyntaxProtocol.Type] = [
        InitializerClauseSyntax.self, ExpressionPatternSyntax.self, DictionaryElementSyntax.self
    ]

    private static let transparentNodes: [SyntaxProtocol.Type] = [
        SequenceExprSyntax.self, ExprListSyntax.self, PrefixOperatorExprSyntax.self, BinaryOperatorExprSyntax.self,
        TupleExprSyntax.self, LabeledExprSyntax.self, LabeledExprListSyntax.self, FunctionCallExprSyntax.self
    ]

    /// Reports whether a statement unconditionally leaves the current block.
    ///
    /// - Parameter item: A block item.
    /// - Returns: Whether it's a `return`, `throw`, `break`, `continue`, or `fallthrough`.
    private func isJump(_ item: CodeBlockItemSyntax.Item) -> Bool {
        item.is(ReturnStmtSyntax.self) || item.is(ThrowStmtSyntax.self) || item.is(BreakStmtSyntax.self)
            || item.is(ContinueStmtSyntax.self) || item.is(FallThroughStmtSyntax.self)
    }

    /// Reports whether an operator sequence sits inside another sequence that holds a ternary.
    ///
    /// - Parameter node: The operator sequence.
    /// - Returns: Whether an enclosing sequence, within the same statement, has a ternary.
    private func hasTernaryAncestor(_ node: SequenceExprSyntax) -> Bool {
        var current = node.parent
        while let parent = current, !parent.is(CodeBlockItemSyntax.self) {
            if let sequence = parent.as(SequenceExprSyntax.self),
               sequence.elements.contains(where: { $0.is(UnresolvedTernaryExprSyntax.self) }) { return true }
            current = parent.parent
        }
        return false
    }
}

extension Trivia {
    /// Whether this trivia contains any comment, doc or otherwise.
    var hasComment: Bool {
        contains {
            switch $0 {
            case .lineComment, .docLineComment, .blockComment, .docBlockComment: return true
            default: return false
            }
        }
    }
}
