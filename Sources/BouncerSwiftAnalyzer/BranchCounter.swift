import SwiftSyntax

/// Counts decision points within a subtree, for an AST-exact cyclomatic complexity.
final class BranchCounter: SyntaxVisitor {
    private(set) var count = 0

    /// Creates a branch counter over a subtree.
    init() {
        super.init(viewMode: .sourceAccurate)
    }

    /// Counts an `if` expression as one decision point.
    ///
    /// - Parameter node: The `if` expression being visited.
    /// - Returns: `.visitChildren`, so nested branches are also counted.
    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        count += 1
        return .visitChildren
    }

    /// Counts a `switch` case as one decision point.
    ///
    /// - Parameter node: The switch case being visited.
    /// - Returns: `.visitChildren`, so nested branches are also counted.
    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        count += 1
        return .visitChildren
    }

    /// Counts a `for` loop as one decision point.
    ///
    /// - Parameter node: The `for` statement being visited.
    /// - Returns: `.visitChildren`, so nested branches are also counted.
    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        count += 1
        return .visitChildren
    }

    /// Counts a `while` loop as one decision point.
    ///
    /// - Parameter node: The `while` statement being visited.
    /// - Returns: `.visitChildren`, so nested branches are also counted.
    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        count += 1
        return .visitChildren
    }

    /// Counts a `repeat`/`while` loop as one decision point.
    ///
    /// - Parameter node: The `repeat` statement being visited.
    /// - Returns: `.visitChildren`, so nested branches are also counted.
    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        count += 1
        return .visitChildren
    }

    /// Counts a `catch` clause as one decision point.
    ///
    /// - Parameter node: The catch clause being visited.
    /// - Returns: `.visitChildren`, so nested branches are also counted.
    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        count += 1
        return .visitChildren
    }

    /// Counts a short-circuiting `&&`/`||` as one additional decision point.
    ///
    /// - Parameter node: The binary operator expression being visited.
    /// - Returns: `.visitChildren`, so nested branches are also counted.
    override func visit(_ node: BinaryOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if node.operator.text == "&&" || node.operator.text == "||" { count += 1 }
        return .visitChildren
    }
}
