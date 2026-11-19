import SwiftSyntax
import BouncerRules

/// Walks a Swift file collecting declared variable and parameter names, and plain string literals.
final class SwiftNameCollector: SyntaxVisitor {
    private(set) var names: [CollectedName] = []
    private(set) var strings: [CollectedString] = []
    /// Every variable, property, and parameter, with its declared or literal type.
    private(set) var typedNames: [CollectedName] = []
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
            let annotated = binding.typeAnnotation?.type.trimmedDescription
            let type = annotated ?? Self.literalType(of: binding.initializer?.value)
            typedNames.append(CollectedName(name: name, line: line(of: binding), typeName: type))
        }
        return .visitChildren
    }

    /// Records a parameter's internal name, the one its body uses.
    ///
    /// - Parameter node: The parameter.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        let name = (node.secondName ?? node.firstName).text
        guard name != "_" else { return .visitChildren }
        names.append(CollectedName(name: name, line: line(of: node)))
        typedNames.append(CollectedName(
            name: name, line: line(of: node), typeName: node.type.trimmedDescription, isParameter: true
        ))
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

    /// Infers a variable's type from a literal or type-constructor initial value, such as `false`,
    /// `[]`, or `Set<Int>()`.
    ///
    /// - Parameter expression: The initial value, if any.
    /// - Returns: The type's name, or `nil` if it isn't obvious.
    private static func literalType(of expression: ExprSyntax?) -> String? {
        guard let expression else { return nil }
        if expression.is(BooleanLiteralExprSyntax.self) { return "Bool" }
        if expression.is(StringLiteralExprSyntax.self) { return "String" }
        if expression.is(IntegerLiteralExprSyntax.self) { return "Int" }
        if expression.is(FloatLiteralExprSyntax.self) { return "Double" }
        if expression.is(ArrayExprSyntax.self) { return "Array" }
        if expression.is(DictionaryExprSyntax.self) { return "Dictionary" }
        return expression.as(FunctionCallExprSyntax.self).flatMap(constructedType)
    }

    /// Reads the type a call constructs, when its callee is a type such as `String` or `[Int]`.
    ///
    /// - Parameter call: The call.
    /// - Returns: The callee's text if it starts with an uppercase letter or `[`, else `nil`.
    private static func constructedType(of call: FunctionCallExprSyntax) -> String? {
        let callee = call.calledExpression.trimmedDescription
        guard let first = callee.first, first.isUppercase || first == "[" else { return nil }
        return callee
    }

    /// Converts a node's position to its 1-indexed line.
    ///
    /// - Parameter node: The node.
    /// - Returns: Its line.
    private func line(of node: some SyntaxProtocol) -> Int {
        converter.location(for: node.positionAfterSkippingLeadingTrivia).line
    }
}
