import SwiftSyntax
import BouncerRules

/// Counts a Swift function body's Halstead operators and operands from its tokens.
///
/// Operands are identifiers, `$0`-style names, number, string-segment, and regex literals, and `true`,
/// `false`, `nil`, `self`, `Self`, and `super`. Every other token is an operator (keywords, punctuation,
/// and operator symbols) except closing brackets and string delimiters, so a bracket pair counts once.
enum SwiftHalstead {
    /// Counts a body's operators and operands.
    ///
    /// - Parameter body: The function's body.
    /// - Returns: Its Halstead counts.
    static func counts(of body: CodeBlockSyntax) -> HalsteadCounts {
        var operators: Set<String> = [], operands: Set<String> = [], totals = (operators: 0, operands: 0)
        for token in body.statements.tokens(viewMode: .sourceAccurate) where !isIgnored(token.tokenKind) {
            let isOperand = isOperand(token.tokenKind)
            if isOperand { operands.insert(token.text) } else { operators.insert(token.text) }
            if isOperand { totals.operands += 1 } else { totals.operators += 1 }
        }
        return HalsteadCounts(distinctOperators: operators.count, distinctOperands: operands.count,
                              totalOperators: totals.operators, totalOperands: totals.operands)
    }

    /// Reports whether a token is an operand.
    ///
    /// - Parameter kind: The token's kind.
    /// - Returns: Whether it names or holds a value.
    private static func isOperand(_ kind: TokenKind) -> Bool {
        switch kind {
        case .identifier, .dollarIdentifier, .integerLiteral, .floatLiteral, .stringSegment, .regexLiteralPattern:
            return true
        case .keyword(.true), .keyword(.false), .keyword(.nil), .keyword(.self), .keyword(.Self), .keyword(.super):
            return true
        default: return false
        }
    }

    /// Reports whether a token is left out of both counts: a closing bracket or a string delimiter.
    ///
    /// - Parameter kind: The token's kind.
    /// - Returns: Whether it's ignored.
    private static func isIgnored(_ kind: TokenKind) -> Bool {
        switch kind {
        case .rightParen, .rightBrace, .rightSquare, .stringQuote, .multilineStringQuote, .singleQuote,
             .rawStringPoundDelimiter, .regexSlash, .regexPoundDelimiter, .endOfFile:
            return true
        default: return false
        }
    }
}
