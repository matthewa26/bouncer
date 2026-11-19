import SwiftSyntax
import BouncerRules

/// Walks a Swift file collecting declared variable and parameter names, and plain string literals.
final class SwiftNameCollector: SyntaxVisitor {
    private(set) var names: [CollectedName] = []
    private(set) var strings: [CollectedString] = []
    private let converter: SourceLocationConverter

    /// Creates a collector for a parsed file.
    ///
    /// - Parameter converter: Converts syntax positions to line numbers.
    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    /// Records each name a `let`/`var` declaration binds.
    ///
    /// - Parameter node: The variable declaration.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
            names.append(CollectedName(name: name, line: line(of: binding)))
        }
        return .visitChildren
    }

    /// Records a parameter's internal name, the one its body uses.
    ///
    /// - Parameter node: The parameter.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        let name = (node.secondName ?? node.firstName).text
        if name != "_" { names.append(CollectedName(name: name, line: line(of: node))) }
        return .visitChildren
    }

    /// Records a string literal with no interpolation.
    ///
    /// - Parameter node: The string literal.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.segments.count == 1, let text = node.segments.first?.as(StringSegmentSyntax.self)?.content.text
        else { return .visitChildren }
        strings.append(CollectedString(text: text, line: line(of: node)))
        return .visitChildren
    }

    /// Converts a node's position to its 1-indexed line.
    ///
    /// - Parameter node: The node.
    /// - Returns: Its line.
    private func line(of node: some SyntaxProtocol) -> Int {
        converter.location(for: node.positionAfterSkippingLeadingTrivia).line
    }
}
