import SwiftSyntax
import BouncerRules

/// Counts a Swift function body's acyclic execution paths (Nejmeh's NPath).
///
/// Statements in sequence multiply; an `if` adds its branches' paths plus one per `&&`/`||` or extra
/// condition clause (and one for a missing `else`); a `guard` and each loop add one for skipping the body;
/// a `switch` sums its cases (Swift's are exhaustive, so a missing `default` adds nothing); a `do`/`catch`
/// sums the body and each handler; a ternary adds its other branch. Closures and nested functions count as
/// one path, and every count saturates at `PathCount.cap`.
enum SwiftPathCounter {
    /// Counts the paths through a node: its own branches if it's a control structure, otherwise the product
    /// of the outermost control structures inside it (everything else runs once).
    ///
    /// - Parameter node: A function body, or any node inside one.
    /// - Returns: Its NPath value.
    static func paths(_ node: Syntax) -> Int {
        if let own = controlPaths(node) { return own }
        let finder = ControlFinder()
        finder.walk(node)
        return finder.found.reduce(1) { PathCount.multiply($0, controlPaths($1) ?? 1) }
    }

    /// Counts the paths through a control structure.
    ///
    /// - Parameter node: Any node.
    /// - Returns: Its paths, or `nil` if it isn't a control structure.
    private static func controlPaths(_ node: Syntax) -> Int? {
        switch node.kind {
        case .closureExpr, .functionDecl: return 1
        case .ifExpr, .guardStmt, .switchExpr, .doStmt: return branchPaths(node)
        case .forStmt, .whileStmt, .repeatStmt: return loopPaths(node)
        case .unresolvedTernaryExpr: return ternaryPaths(node)
        default: return nil
        }
    }

    /// Collects the outermost control structures in a subtree, without looking inside them.
    private final class ControlFinder: SyntaxVisitor {
        private(set) var found: [Syntax] = []

        /// Creates a finder.
        init() {
            super.init(viewMode: .sourceAccurate)
        }

        /// Records an `if`.
        ///
        /// - Parameter node: The `if`.
        /// - Returns: `.skipChildren`.
        override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind { record(node) }

        /// Records a `guard`.
        ///
        /// - Parameter node: The `guard`.
        /// - Returns: `.skipChildren`.
        override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind { record(node) }

        /// Records a `switch`.
        ///
        /// - Parameter node: The `switch`.
        /// - Returns: `.skipChildren`.
        override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind { record(node) }

        /// Records a `do`.
        ///
        /// - Parameter node: The `do`.
        /// - Returns: `.skipChildren`.
        override func visit(_ node: DoStmtSyntax) -> SyntaxVisitorContinueKind { record(node) }

        /// Records a `for` loop.
        ///
        /// - Parameter node: The loop.
        /// - Returns: `.skipChildren`.
        override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind { record(node) }

        /// Records a `while` loop.
        ///
        /// - Parameter node: The loop.
        /// - Returns: `.skipChildren`.
        override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind { record(node) }

        /// Records a `repeat` loop.
        ///
        /// - Parameter node: The loop.
        /// - Returns: `.skipChildren`.
        override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind { record(node) }

        /// Records a ternary.
        ///
        /// - Parameter node: The unfolded ternary.
        /// - Returns: `.skipChildren`.
        override func visit(_ node: UnresolvedTernaryExprSyntax) -> SyntaxVisitorContinueKind { record(node) }

        /// Records a closure, which counts as one path, without looking inside.
        ///
        /// - Parameter node: The closure.
        /// - Returns: `.skipChildren`.
        override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind { record(node) }

        /// Records a nested function, which counts as one path, without looking inside.
        ///
        /// - Parameter node: The function.
        /// - Returns: `.skipChildren`.
        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { record(node) }

        /// Records a control structure.
        ///
        /// - Parameter node: The structure.
        /// - Returns: `.skipChildren`, since its own paths cover its insides.
        private func record(_ node: some SyntaxProtocol) -> SyntaxVisitorContinueKind {
            found.append(Syntax(node))
            return .skipChildren
        }
    }

    /// Counts the paths through a ternary: its `then` branch's, plus the other branch.
    ///
    /// - Parameter node: The unfolded ternary.
    /// - Returns: Its paths.
    private static func ternaryPaths(_ node: Syntax) -> Int {
        let then = node.as(UnresolvedTernaryExprSyntax.self).map { paths(Syntax($0.thenExpression)) } ?? 1
        return PathCount.add(then, 1)
    }

    /// Counts the paths through an `if`, `guard`, `switch`, or `do`/`catch`.
    ///
    /// - Parameter node: Any node.
    /// - Returns: Its paths, or `nil` if it isn't one of those.
    private static func branchPaths(_ node: Syntax) -> Int? {
        if let branch = node.as(IfExprSyntax.self) {
            let otherwise = branch.elseBody.map { paths(Syntax($0)) } ?? 1
            return PathCount.add(conditions(Syntax(branch.conditions)) + paths(Syntax(branch.body)), otherwise)
        }
        if let guardStmt = node.as(GuardStmtSyntax.self) {
            return PathCount.add(conditions(Syntax(guardStmt.conditions)) + 1, paths(Syntax(guardStmt.body)))
        }
        return alternativePaths(node)
    }

    /// Counts the paths through a `switch` or `do`/`catch`.
    ///
    /// - Parameter node: Any node.
    /// - Returns: Its paths, or `nil` if it isn't one of those.
    private static func alternativePaths(_ node: Syntax) -> Int? {
        if let switchExpr = node.as(SwitchExprSyntax.self) { return sum(switchExpr.cases.map(Syntax.init)) }
        guard let doStmt = node.as(DoStmtSyntax.self) else { return nil }
        return PathCount.add(paths(Syntax(doStmt.body)), sum(doStmt.catchClauses.map { Syntax($0.body) }))
    }

    /// Counts the paths through a loop: its body, or skipping it.
    ///
    /// - Parameter node: Any node.
    /// - Returns: Its paths, or `nil` if it isn't a loop.
    private static func loopPaths(_ node: Syntax) -> Int? {
        if let loop = node.as(ForStmtSyntax.self) {
            let filter = loop.whereClause.map { conditions(Syntax($0)) + 1 } ?? 0
            return PathCount.add(paths(Syntax(loop.body)) + 1, filter)
        }
        if let loop = node.as(WhileStmtSyntax.self) {
            return PathCount.add(paths(Syntax(loop.body)) + 1, conditions(Syntax(loop.conditions)))
        }
        guard let loop = node.as(RepeatStmtSyntax.self) else { return nil }
        return PathCount.add(paths(Syntax(loop.body)) + 1, conditions(Syntax(loop.condition)))
    }

    /// Adds up the paths of alternatives, such as a switch's cases.
    ///
    /// - Parameter nodes: The alternatives.
    /// - Returns: The sum of their paths.
    private static func sum(_ nodes: [Syntax]) -> Int {
        nodes.reduce(0) { PathCount.add($0, paths($1)) }
    }

    /// Counts the extra paths a condition opens: each `&&`/`||`, and each clause after the first.
    ///
    /// - Parameter node: A condition list or expression.
    /// - Returns: The extra paths.
    private static func conditions(_ node: Syntax) -> Int {
        let operators = node.tokens(viewMode: .sourceAccurate).filter { $0.text == "&&" || $0.text == "||" }.count
        let clauses = node.as(ConditionElementListSyntax.self).map { max(0, $0.count - 1) } ?? 0
        return operators + clauses
    }
}
