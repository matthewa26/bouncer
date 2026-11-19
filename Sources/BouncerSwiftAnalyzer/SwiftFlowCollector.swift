import SwiftSyntax
import BouncerRules

/// Walks one Swift function body for its `if` pyramids, loop jumps, and unconditional recursion.
///
/// Jumps go to their target the way Swift resolves them: an unlabeled `break` to the innermost loop or
/// `switch`, an unlabeled `continue` to the innermost loop, and a labeled one to the statement with that
/// label; only jumps out of loops count. A self-call is an unqualified or `self.` call with the
/// function's name and argument labels, outside closures and nested functions; it has no base case when
/// the body has no `if`, `guard`, `switch`, loop, ternary, `catch`, `throw`, `&&`/`||`/`??`, `try?`, or
/// optional chaining anywhere in it.
final class SwiftFlowCollector: SyntaxVisitor {
    /// A statement a jump can target; `isLoop` is false for a `switch`.
    private struct Target {
        let label: String?
        let isLoop: Bool
        var jumps = 0
    }

    private let signature: SwiftCallSignature?
    /// Jump targets, innermost last; `nil` marks a closure or nested function, which jumps can't leave.
    private var targets: [Target?] = []
    private var maxLoopJumps = 0
    private var arrowDepth = 0
    private var selfCalls = 0

    /// Creates a collector.
    ///
    /// - Parameter signature: The function's name and argument labels, or `nil` to skip the recursion check.
    init(signature: SwiftCallSignature?) {
        self.signature = signature
        super.init(viewMode: .sourceAccurate)
    }

    /// Measures a function body.
    ///
    /// - Parameters:
    ///   - body: The function's body.
    ///   - signature: Its name and argument labels, or `nil` to skip the recursion check.
    /// - Returns: Its flow measurements.
    static func measure(_ body: CodeBlockSyntax, signature: SwiftCallSignature?) -> FlowMetrics {
        let collector = SwiftFlowCollector(signature: signature)
        collector.arrowDepth = SwiftArrowDepth.depth(of: body)
        collector.walk(body)
        return FlowMetrics(
            npath: SwiftPathCounter.paths(Syntax(body)), arrowDepth: collector.arrowDepth,
            maxLoopJumps: collector.maxLoopJumps,
            recursesWithoutBaseCase: collector.selfCalls > 0 && !SwiftArrowDepth.canStop(body)
        )
    }

    /// Opens a `for` loop's jump target.
    ///
    /// - Parameter node: The loop.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        openLoop(Syntax(node), body: node.body)
    }

    /// Closes a `for` loop's jump target.
    ///
    /// - Parameter node: The loop.
    override func visitPost(_ node: ForStmtSyntax) { close() }

    /// Opens a `while` loop's jump target.
    ///
    /// - Parameter node: The loop.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        openLoop(Syntax(node), body: node.body)
    }

    /// Closes a `while` loop's jump target.
    ///
    /// - Parameter node: The loop.
    override func visitPost(_ node: WhileStmtSyntax) { close() }

    /// Opens a `repeat` loop's jump target.
    ///
    /// - Parameter node: The loop.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        openLoop(Syntax(node), body: node.body)
    }

    /// Closes a `repeat` loop's jump target.
    ///
    /// - Parameter node: The loop.
    override func visitPost(_ node: RepeatStmtSyntax) { close() }

    /// Opens a `switch`'s jump target, which an unlabeled `break` leaves without leaving a loop.
    ///
    /// - Parameter node: The switch.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        targets.append(Target(label: label(of: Syntax(node)), isLoop: false))
        return .visitChildren
    }

    /// Closes a `switch`'s jump target.
    ///
    /// - Parameter node: The switch.
    override func visitPost(_ node: SwitchExprSyntax) { close() }

    /// Bars jumps and self-calls inside a closure from counting toward the function.
    ///
    /// - Parameter node: The closure.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind { openBarrier() }

    /// Lifts a closure's barrier.
    ///
    /// - Parameter node: The closure.
    override func visitPost(_ node: ClosureExprSyntax) { close() }

    /// Bars jumps and self-calls inside a nested function from counting toward the function.
    ///
    /// - Parameter node: The nested function.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { openBarrier() }

    /// Lifts a nested function's barrier.
    ///
    /// - Parameter node: The nested function.
    override func visitPost(_ node: FunctionDeclSyntax) { close() }

    /// Counts a `break` toward the loop it leaves.
    ///
    /// - Parameter node: The statement.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: BreakStmtSyntax) -> SyntaxVisitorContinueKind {
        countJump(label: node.label?.text, loopsOnly: false)
    }

    /// Counts a `continue` toward the loop it restarts.
    ///
    /// - Parameter node: The statement.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ContinueStmtSyntax) -> SyntaxVisitorContinueKind {
        countJump(label: node.label?.text, loopsOnly: true)
    }

    /// Counts a call to the function itself.
    ///
    /// - Parameter node: The call.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if isAtTopLevel, signature?.matches(node) == true { selfCalls += 1 }
        return .visitChildren
    }

    /// Whether the walk is outside every closure and nested function.
    private var isAtTopLevel: Bool { !targets.contains { $0 == nil } }

    /// Reads the label a labeled statement gives a node.
    ///
    /// - Parameter node: A loop or switch.
    /// - Returns: The label, or `nil`.
    private func label(of node: Syntax) -> String? {
        node.parent?.as(LabeledStmtSyntax.self)?.label.text
    }

    /// Opens a loop's jump target and measures the `if` pyramid ending its body.
    ///
    /// - Parameters:
    ///   - node: The loop.
    ///   - body: Its body.
    /// - Returns: `.visitChildren`.
    private func openLoop(_ node: Syntax, body: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        if isAtTopLevel { arrowDepth = max(arrowDepth, SwiftArrowDepth.depth(of: body)) }
        targets.append(Target(label: label(of: node), isLoop: true))
        return .visitChildren
    }

    /// Opens a barrier for a closure or nested function.
    ///
    /// - Returns: `.visitChildren`.
    private func openBarrier() -> SyntaxVisitorContinueKind {
        targets.append(nil)
        return .visitChildren
    }

    /// Closes the innermost jump target or barrier, recording a loop's jump count.
    private func close() {
        guard let last = targets.popLast(), let last, last.isLoop else { return }
        maxLoopJumps = max(maxLoopJumps, last.jumps)
    }

    /// Credits a jump to its target, if that target is a loop.
    ///
    /// - Parameters:
    ///   - label: The jump's label, if any.
    ///   - loopsOnly: Whether only a loop can be its unlabeled target (`continue`) or a `switch` too (`break`).
    /// - Returns: `.visitChildren`.
    private func countJump(label: String?, loopsOnly: Bool) -> SyntaxVisitorContinueKind {
        for index in targets.indices.reversed() {
            guard let target = targets[index] else { break }
            let isTarget = label.map { target.label == $0 } ?? (target.isLoop || !loopsOnly)
            guard isTarget else { continue }
            if target.isLoop { targets[index]?.jumps += 1 }
            break
        }
        return .visitChildren
    }
}

/// A Swift function's name and argument labels, for recognizing a call to itself.
struct SwiftCallSignature {
    let name: String
    /// Each parameter's argument label, with `_` for an unlabeled one.
    let labels: [String]

    /// Reports whether a call invokes this function: `name(…)` or `self.name(…)` with the same labels. A
    /// call converting an argument, as in `ioctl(CInt(a))`, likely means a same-labeled overload elsewhere.
    ///
    /// - Parameter call: The call.
    /// - Returns: Whether it's a self-call.
    func matches(_ call: FunctionCallExprSyntax) -> Bool {
        guard call.trailingClosure == nil, call.arguments.map({ $0.label?.text ?? "_" }) == labels,
              !call.arguments.contains(where: { Self.isConversion($0.expression) }) else { return false }
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text == name
        }
        guard let member = call.calledExpression.as(MemberAccessExprSyntax.self) else { return false }
        let isOnSelf = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "self"
        return member.declName.baseName.text == name && isOnSelf
    }

    /// Reports whether an argument converts a value to another type, such as `Double(x)`.
    ///
    /// - Parameter expression: The argument.
    /// - Returns: Whether it calls an uppercase name.
    private static func isConversion(_ expression: ExprSyntax) -> Bool {
        let callee = expression.as(FunctionCallExprSyntax.self)?.calledExpression.as(DeclReferenceExprSyntax.self)
        return callee?.baseName.text.first?.isUppercase ?? false
    }
}
