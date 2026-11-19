import SwiftSyntax
import BouncerRules

/// Reads a Swift declaration's doc comment and the signature facts the doc-completeness rules check.
enum SwiftDocumentation {
    private static let voidTypes: Set<String> = ["Void", "()", "Never"]

    /// Gathers a function's doc comment and signature facts.
    ///
    /// - Parameters:
    ///   - trivia: The declaration's leading trivia, holding its `///` or `/** */` comment.
    ///   - signature: Its signature.
    ///   - body: Its body, to tell a function that throws from one marked `throws` only to match a protocol.
    /// - Returns: The facts, or `nil` without a doc comment.
    static func facts(
        trivia: Trivia, signature: FunctionSignatureSyntax, body: CodeBlockSyntax
    ) -> DocumentationFacts? {
        let lines = trivia.compactMap(docText)
        guard !lines.isEmpty else { return nil }
        let isThrowing = signature.effectSpecifiers?.throwsSpecifier?.tokenKind == .keyword(.throws)
        return DocumentationFacts(
            style: .swift, text: lines.joined(separator: "\n"),
            parameters: signature.parameterClause.parameters.compactMap(parameter),
            returnsValue: returnsValue(signature), throwsError: isThrowing && canThrow(body)
        )
    }

    /// Reports whether a body can throw: it has a `throw`, or a `try` that isn't `try?` or `try!`.
    ///
    /// - Parameter body: The function's body.
    /// - Returns: Whether an error can escape it.
    private static func canThrow(_ body: CodeBlockSyntax) -> Bool {
        let tokens = Array(body.tokens(viewMode: .sourceAccurate))
        return tokens.indices.contains { index in
            if tokens[index].tokenKind == .keyword(.throw) { return true }
            guard tokens[index].tokenKind == .keyword(.try), index + 1 < tokens.count else { return false }
            return ![.postfixQuestionMark, .exclamationMark].contains(tokens[index + 1].tokenKind)
        }
    }

    /// Reads a trivia piece's text if it's a doc comment.
    ///
    /// - Parameter piece: A trivia piece.
    /// - Returns: The `///` or `/** */` comment's text, or `nil` for anything else.
    private static func docText(_ piece: TriviaPiece) -> String? {
        switch piece {
        case .docLineComment(let text), .docBlockComment(let text): return text
        default: return nil
        }
    }

    /// Reads a parameter's names: the one the body uses, and its argument label as an alias.
    ///
    /// - Parameter parameter: The parameter.
    /// - Returns: Its names, or `nil` for an unnamed `_` parameter.
    private static func parameter(_ parameter: FunctionParameterSyntax) -> SignatureParameter? {
        let label = parameter.firstName.text
        let local = parameter.secondName?.text ?? label
        guard local != "_" else { return label == "_" ? nil : SignatureParameter(name: label) }
        return SignatureParameter(name: local, aliases: label == "_" || label == local ? [] : [label])
    }

    /// Reports whether a signature returns a value: a return type other than `Void`, `()`, or `Never`.
    ///
    /// - Parameter signature: The signature.
    /// - Returns: Whether it returns a value.
    private static func returnsValue(_ signature: FunctionSignatureSyntax) -> Bool {
        guard let type = signature.returnClause?.type else { return false }
        if let tuple = type.as(TupleTypeSyntax.self) { return !tuple.elements.isEmpty }
        return !voidTypes.contains(type.as(IdentifierTypeSyntax.self)?.name.text ?? "")
    }
}
