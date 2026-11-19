import SwiftSyntax

/// Classifies Swift control flow for `SwiftFlowCollector`: `if` pyramids, and the branches
/// that give recursion a base case.
enum SwiftArrowDepth {
    private static let shortCircuits: Set<String> = ["&&", "||", "??"]

    /// Measures the `if` pyramid ending a block: an `if` without `else` as its last statement counts one,
    /// plus the pyramid ending that `if`'s own body. Each such `if` could be a `guard` that exits early.
    ///
    /// - Parameter block: A function or loop body.
    /// - Returns: The pyramid's depth; 0 if the block doesn't end in an `if` without `else`.
    static func depth(of block: CodeBlockSyntax) -> Int {
        guard let last = block.statements.last, let branch = ifStatement(last.item), branch.elseBody == nil else {
            return 0
        }
        return 1 + depth(of: branch.body)
    }

    /// Unwraps an `if` used as a statement.
    ///
    /// - Parameter item: A block item.
    /// - Returns: The `if`, or `nil` for any other statement.
    private static func ifStatement(_ item: CodeBlockItemSyntax.Item) -> IfExprSyntax? {
        switch item {
        case .expr(let expression): return expression.as(IfExprSyntax.self)
        case .stmt(let statement): return statement.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self)
        default: return nil
        }
    }

    /// Reports whether a body could stop a recursion: any branch, loop, early exit, or short circuit, found
    /// by its tokens (`if`, `guard`, `switch`, `for`, `while`, `repeat`, `catch`, `throw`, `?`, `&&`, `||`,
    /// `??`). One inside a closure counts too, which errs toward not reporting.
    ///
    /// - Parameter body: The function's body.
    /// - Returns: Whether it holds anything conditional.
    static func canStop(_ body: CodeBlockSyntax) -> Bool {
        body.tokens(viewMode: .sourceAccurate).contains { isConditional($0.tokenKind) }
    }

    /// Reports whether a token marks a branch, loop, early exit, or short circuit.
    ///
    /// - Parameter kind: The token's kind.
    /// - Returns: Whether it's conditional.
    private static func isConditional(_ kind: TokenKind) -> Bool {
        switch kind {
        case .keyword(.if), .keyword(.guard), .keyword(.switch), .keyword(.for), .keyword(.while),
             .keyword(.repeat), .keyword(.catch), .keyword(.throw), .postfixQuestionMark, .infixQuestionMark:
            return true
        case .binaryOperator(let text): return shortCircuits.contains(text)
        default: return false
        }
    }
}
