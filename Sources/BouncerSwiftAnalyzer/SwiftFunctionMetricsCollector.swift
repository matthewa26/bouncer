import SwiftSyntax
import BouncerRules

/// Walks one function body, measuring its returns, cognitive complexity, and nesting depth.
///
/// Cognitive complexity follows SonarSource's scheme: each `if`, loop, `switch`,
/// `catch`, and ternary adds one plus the current nesting level; `else` and
/// `else if` add one flat; each run of mixed `&&`/`||` adds one; and closures and
/// nested functions deepen nesting without scoring. Recursion and labeled jumps
/// aren't counted.
final class SwiftFunctionMetricsCollector: SyntaxVisitor {
    private var returnCount = 0
    private var score = 0
    private var nesting = 0
    private var controlDepth = 0
    private var maxControlDepth = 0
    private var closureDepth = 0

    /// Creates a collector.
    init() {
        super.init(viewMode: .sourceAccurate)
    }

    /// Measures a function body.
    ///
    /// - Parameters:
    ///   - body: The function's body block.
    ///   - parameterCount: The function's declared parameter count.
    /// - Returns: The function's measurements.
    static func measure(_ body: CodeBlockSyntax, parameterCount: Int) -> FunctionMetrics {
        let collector = SwiftFunctionMetricsCollector()
        collector.walk(body)
        return FunctionMetrics(
            parameterCount: parameterCount, returnCount: collector.returnCount,
            cognitiveComplexity: collector.score, maxNestingDepth: collector.maxControlDepth
        )
    }

    /// Scores an `if`, treating `else if` as a flat increment that doesn't deepen nesting.
    ///
    /// - Parameter node: The `if` expression.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        if node.elseBody?.is(CodeBlockSyntax.self) == true { score += 1 }
        if isElseIf(node) {
            score += 1
            return .visitChildren
        }
        enterControl()
        return .visitChildren
    }

    /// Leaves an `if`'s nesting level, unless it was an `else if` that never entered one.
    ///
    /// - Parameter node: The `if` expression.
    override func visitPost(_ node: IfExprSyntax) {
        if !isElseIf(node) { leaveControl() }
    }

    /// Scores a `for` loop.
    ///
    /// - Parameter node: The loop.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind { enterControl() }

    /// Leaves a `for` loop's nesting level.
    ///
    /// - Parameter node: The loop.
    override func visitPost(_ node: ForStmtSyntax) { leaveControl() }

    /// Scores a `while` loop.
    ///
    /// - Parameter node: The loop.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind { enterControl() }

    /// Leaves a `while` loop's nesting level.
    ///
    /// - Parameter node: The loop.
    override func visitPost(_ node: WhileStmtSyntax) { leaveControl() }

    /// Scores a `repeat` loop.
    ///
    /// - Parameter node: The loop.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind { enterControl() }

    /// Leaves a `repeat` loop's nesting level.
    ///
    /// - Parameter node: The loop.
    override func visitPost(_ node: RepeatStmtSyntax) { leaveControl() }

    /// Scores a `switch`.
    ///
    /// - Parameter node: The switch.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind { enterControl() }

    /// Leaves a `switch`'s nesting level.
    ///
    /// - Parameter node: The switch.
    override func visitPost(_ node: SwitchExprSyntax) { leaveControl() }

    /// Scores a `catch` clause.
    ///
    /// - Parameter node: The catch clause.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind { enterControl() }

    /// Leaves a `catch` clause's nesting level.
    ///
    /// - Parameter node: The catch clause.
    override func visitPost(_ node: CatchClauseSyntax) { leaveControl() }

    /// Scores a ternary at the current nesting level.
    ///
    /// - Parameter node: The unfolded ternary.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: UnresolvedTernaryExprSyntax) -> SyntaxVisitorContinueKind {
        score += 1 + nesting
        return .visitChildren
    }

    /// Scores each run of mixed logical operators in an operator sequence.
    ///
    /// - Parameter node: The operator sequence.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let logical = node.elements.compactMap { $0.as(BinaryOperatorExprSyntax.self)?.operator.text }
            .filter { $0 == "&&" || $0 == "||" }
        score += zip(logical, [""] + logical).filter { $0 != $1 }.count
        return .visitChildren
    }

    /// Deepens nesting inside a closure without scoring it.
    ///
    /// - Parameter node: The closure.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        nesting += 1
        closureDepth += 1
        return .visitChildren
    }

    /// Leaves a closure's nesting level.
    ///
    /// - Parameter node: The closure.
    override func visitPost(_ node: ClosureExprSyntax) {
        nesting -= 1
        closureDepth -= 1
    }

    /// Deepens nesting inside a nested function without scoring it.
    ///
    /// - Parameter node: The nested function.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        nesting += 1
        closureDepth += 1
        return .visitChildren
    }

    /// Leaves a nested function's nesting level.
    ///
    /// - Parameter node: The nested function.
    override func visitPost(_ node: FunctionDeclSyntax) {
        nesting -= 1
        closureDepth -= 1
    }

    /// Counts a `return` that belongs to this function, not to a nested closure or function.
    ///
    /// - Parameter node: The return statement.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
        if closureDepth == 0 { returnCount += 1 }
        return .visitChildren
    }

    /// Scores a nesting structure and enters its nesting level.
    ///
    /// - Returns: `.visitChildren`, so callers can return it directly.
    private func enterControl() -> SyntaxVisitorContinueKind {
        score += 1 + nesting
        nesting += 1
        controlDepth += 1
        maxControlDepth = max(maxControlDepth, controlDepth)
        return .visitChildren
    }

    /// Leaves a nesting structure's level.
    private func leaveControl() {
        nesting -= 1
        controlDepth -= 1
    }

    /// Reports whether an `if` is the `else if` branch of another `if`.
    ///
    /// - Parameter node: The `if` expression.
    /// - Returns: Whether its parent is an `if` holding it as the else branch.
    private func isElseIf(_ node: IfExprSyntax) -> Bool {
        node.parent?.as(IfExprSyntax.self)?.elseBody?.id == node.id
    }
}
