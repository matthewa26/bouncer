import SwiftSyntax
import BouncerRules

/// Records each outermost member chain's reach past its first object, for `law-of-demeter`.
final class SwiftDemeterCollector: SyntaxVisitor {
    private let converter: SourceLocationConverter
    private(set) var markers: [CollectedMarker] = []

    /// Creates a collector for a parsed file.
    ///
    /// - Parameter converter: Converts syntax positions to line numbers.
    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    /// Measures the chain this member access ends, if it's the outermost one.
    ///
    /// - Parameter node: A member access.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        guard let top = chainTop(node) else { return .visitChildren }
        let (base, segments) = decompose(top)
        let reach = DemeterChain.reach(base: base, segments: segments)
        guard reach > 0 else { return .visitChildren }
        let line = converter.location(for: top.positionAfterSkippingLeadingTrivia).line
        markers.append(CollectedMarker(kind: .lawOfDemeter, line: line, value: reach))
        return .visitChildren
    }

    /// Climbs from a member access through calls and `?`/`!` to the whole chain it belongs to.
    ///
    /// - Parameter node: A member access.
    /// - Returns: The chain's outermost expression, or `nil` if a further member access continues it.
    private func chainTop(_ node: MemberAccessExprSyntax) -> ExprSyntax? {
        var current = Syntax(node)
        while let parent = current.parent, continues(parent, from: current) {
            if parent.is(MemberAccessExprSyntax.self) { return nil }
            current = parent
        }
        return current.as(ExprSyntax.self)
    }

    /// Reports whether a parent extends the chain its child is part of.
    ///
    /// - Parameters:
    ///   - parent: The parent node.
    ///   - child: The child, part of a chain.
    /// - Returns: Whether the parent accesses a member of the child, calls it, or unwraps it.
    private func continues(_ parent: Syntax, from child: Syntax) -> Bool {
        if let member = parent.as(MemberAccessExprSyntax.self) { return member.base?.id == child.id }
        if let call = parent.as(FunctionCallExprSyntax.self) { return call.calledExpression.id == child.id }
        return parent.is(OptionalChainingExprSyntax.self) || parent.is(ForceUnwrapExprSyntax.self)
    }

    /// Splits a chain into the name it starts from and its member accesses.
    ///
    /// - Parameters:
    ///   - expression: The chain's outermost expression, or a part of it.
    ///   - isCalled: Whether the caller calls this part.
    /// - Returns: The base name (`nil` for a literal or other expression) and the segments, in order.
    private func decompose(_ expression: ExprSyntax, isCalled: Bool = false) -> (String?, [DemeterChain.Segment]) {
        if let (inner, calls) = passThrough(expression) { return decompose(inner, isCalled: isCalled || calls) }
        guard let member = expression.as(MemberAccessExprSyntax.self) else {
            return (expression.as(DeclReferenceExprSyntax.self)?.baseName.text, [])
        }
        let segment = DemeterChain.Segment(name: member.declName.baseName.text, isCall: isCalled)
        let (name, segments) = member.base.map { decompose($0) } ?? (nil, [])
        return (name, segments + [segment])
    }

    /// Looks through a call to its callee, or through `?`/`!` to the unwrapped expression.
    ///
    /// - Parameter expression: Any expression.
    /// - Returns: The inner expression and whether it's called, or `nil` for any other expression.
    private func passThrough(_ expression: ExprSyntax) -> (ExprSyntax, Bool)? {
        if let call = expression.as(FunctionCallExprSyntax.self) { return (call.calledExpression, true) }
        let unwrapped = expression.as(OptionalChainingExprSyntax.self)?.expression
            ?? expression.as(ForceUnwrapExprSyntax.self)?.expression
        return unwrapped.map { ($0, false) }
    }
}
