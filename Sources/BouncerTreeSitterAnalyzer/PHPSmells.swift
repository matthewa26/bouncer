import Foundation
import SwiftTreeSitter
import BouncerCore

/// PHP's own smells, found in one walk of a file's tree.
///
/// - `php-debug-output`: a call to `var_dump`, `print_r`, `dd`, or `dump` outside test code. `print_r($x, true)`
///   returns the dump as a string instead of printing it, so it isn't flagged, and neither is a dump after an
///   `ob_start()` in the same function, whose output is captured on purpose.
/// - `php-eval`: `eval(…)` or `create_function(…)`, which run a string as code.
/// - `php-error-suppression`: the `@` operator, which hides every error its expression raises.
/// - `php-extract`: `extract()` of a superglobal (`$_GET`, `$_POST`, …), which lets a request set any local.
/// - `php-loose-comparison`: `==`, `!=`, or `<>` with a variable, property, or call named like a hash, token,
///   password, signature, secret, nonce, or HMAC on either side, which type juggling and timing can defeat. A
///   comparison with `null` isn't checked.
///
/// Test code is a file under a `tests/` or `test/` folder, or a `…Test.php` file (see `PHPSyntax.isTestPath`).
/// A function is only matched by its global name (`var_dump`, `\var_dump`), never as a method (`$c->dump()`).
struct PHPSmells: LanguageSmellExtractor {
    /// Lists a PHP file's smells.
    ///
    /// - Parameter tree: The parsed file.
    /// - Returns: One finding per smell whose rule is enabled.
    func findings(in tree: SmellTree) -> [Finding] {
        let check = PHPSmellCheck(tree: tree)
        var findings: [Finding] = []
        TreeWalk.forEach(tree.root) { findings += check.findings(at: $0) }
        return findings
    }
}

/// The per-node checks behind `PHPSmells`.
struct PHPSmellCheck {
    private static let debugFunctions: Set<String> = ["var_dump", "print_r", "dd", "dump"]
    private static let evalFunctions: Set<String> = ["eval", "create_function"]
    private static let superglobals: Set<String> = [
        "$_GET", "$_POST", "$_REQUEST", "$_COOKIE", "$_FILES", "$_SERVER", "$_ENV"
    ]
    private static let looseOperators: Set<String> = ["==", "!=", "<>"]
    private static let secretName = #"(?i)hash|token|passw(or)?d|signature|secret|nonce|hmac"#
    /// Calls and property reads, mapped to the field naming what they call or read.
    private static let namedAccess = [
        "member_access_expression": "name", "nullsafe_member_access_expression": "name",
        "scoped_property_access_expression": "name", "member_call_expression": "name",
        "nullsafe_member_call_expression": "name", "scoped_call_expression": "name",
        "function_call_expression": "function"
    ]

    private let tree: SmellTree
    /// Whether the file is test code, where dumping a value is fine.
    private let isTestCode: Bool

    /// Prepares the checks for one file.
    ///
    /// - Parameter tree: The parsed file.
    init(tree: SmellTree) {
        self.tree = tree
        isTestCode = PHPSyntax.isTestPath(tree.file.relativePath(under: tree.context.repoRoot))
    }

    /// Checks one node for each smell its type can have.
    ///
    /// - Parameter node: The node.
    /// - Returns: Its findings; usually none.
    func findings(at node: Node) -> [Finding] {
        switch node.nodeType {
        case "function_call_expression": return callFinding(node).map { [$0] } ?? []
        case "error_suppression_expression":
            return [tree.finding("php-error-suppression", at: node,
                                 "The @ operator hides every error this expression raises; handle the failure.")]
                .compactMap { $0 }
        case PHPNode.binaryExpression: return looseComparison(node).map { [$0] } ?? []
        default: return []
        }
    }

    /// Flags a call to a debug-output, `eval`-like, or `extract` function.
    ///
    /// - Parameter call: A function call.
    /// - Returns: Its finding, or `nil`.
    private func callFinding(_ call: Node) -> Finding? {
        guard let name = globalName(of: call), let (ruleID, message) = smell(of: call, name: name) else { return nil }
        return tree.finding(ruleID, at: call, message)
    }

    /// Judges a call to a global function by its name and arguments.
    ///
    /// - Parameters:
    ///   - call: The function call.
    ///   - name: The function's lowercased name.
    /// - Returns: The rule it breaks and what to say, or `nil` for a fine call.
    private func smell(of call: Node, name: String) -> (ruleID: String, message: String)? {
        if Self.evalFunctions.contains(name) {
            return ("php-eval", name + "() runs a string as code; call the code directly instead.")
        }
        if name == "extract" {
            return isSuperglobal(arguments(of: call).first)
                ? ("php-extract", "extract() of request data lets the caller set any local.") : nil
        }
        return debugOutput(call, name: name)
    }

    /// Flags a debug dump that prints: outside test code, not returned as a string, and not captured by an output
    /// buffer.
    ///
    /// - Parameters:
    ///   - call: The call.
    ///   - name: The function's name.
    /// - Returns: The rule it breaks and what to say, or `nil` for a fine call.
    private func debugOutput(_ call: Node, name: String) -> (ruleID: String, message: String)? {
        guard Self.debugFunctions.contains(name), !isTestCode, printsOutput(call, name: name), !isBuffered(call)
        else { return nil }
        return ("php-debug-output", "Remove " + name + "() debug output, or log it instead.")
    }

    /// Names the global function a call calls, as written plainly or from the root namespace (`\var_dump`).
    ///
    /// - Parameter call: A function call.
    /// - Returns: Its lowercased name, or `nil` for a namespaced or dynamic callee.
    private func globalName(of call: Node) -> String? {
        guard let callee = call.child(byFieldName: "function"), let written = tree.text(of: callee) else { return nil }
        let name = written.hasPrefix("\\") ? String(written.dropFirst()) : written
        guard callee.nodeType == "name" || (callee.nodeType == "qualified_name" && !name.contains("\\")) else {
            return nil
        }
        return name.lowercased()
    }

    /// Lists a call's arguments, unwrapped from their `argument` nodes.
    ///
    /// - Parameter call: A call.
    /// - Returns: Each argument's expression, in order.
    private func arguments(of call: Node) -> [Node] {
        guard let list = call.child(byFieldName: "arguments") else { return [] }
        let wrapped = TreeWalk.namedChildren(list).filter { $0.nodeType == PHPNode.argument }
        return wrapped.compactMap { $0.namedChild(at: 0) }
    }

    /// Reports whether an expression is a request superglobal, such as `$_GET`.
    ///
    /// - Parameter node: The expression, if any.
    /// - Returns: Whether it's one of the superglobals a request fills.
    private func isSuperglobal(_ node: Node?) -> Bool {
        guard let node, node.nodeType == "variable_name", let name = tree.text(of: node) else { return false }
        return Self.superglobals.contains(name)
    }

    /// Reports whether a call runs inside output buffering that an `ob_start()` earlier in its function (or, at the
    /// top level, its file) opened, so what it prints is captured on purpose rather than left over.
    ///
    /// - Parameter call: A call.
    /// - Returns: Whether an `ob_start(` comes before it in its scope.
    private func isBuffered(_ call: Node) -> Bool {
        var scope = call
        while let parent = scope.parent, !TreeSitterLanguageSpec.php.functionNodeTypes.contains(scope.nodeType ?? "") {
            scope = parent
        }
        guard let text = tree.text(of: scope).map({ $0 as NSString }) else { return false }
        let offset = min(max(0, call.range.location - scope.range.location), text.length)
        return text.substring(to: offset).contains("ob_start(")
    }

    /// Reports whether a debug function prints: every one does, except `print_r` given a return flag other than
    /// a literal `false`.
    ///
    /// - Parameters:
    ///   - call: The call.
    ///   - name: The function's name.
    /// - Returns: Whether the call prints.
    private func printsOutput(_ call: Node, name: String) -> Bool {
        let flag = arguments(of: call).dropFirst().first
        guard name == "print_r", let flag else { return true }
        return tree.text(of: flag)?.lowercased() == "false"
    }

    /// Flags a loose comparison of a secret-like value.
    ///
    /// - Parameter node: A binary expression.
    /// - Returns: Its finding, or `nil`.
    private func looseComparison(_ node: Node) -> Finding? {
        guard let op = node.child(byFieldName: "operator").flatMap(tree.text), Self.looseOperators.contains(op),
              let left = node.child(byFieldName: "left"), let right = node.child(byFieldName: "right"),
              left.nodeType != "null", right.nodeType != "null", isSecret(left) || isSecret(right) else { return nil }
        return tree.finding("php-loose-comparison", at: node,
                            "Loose " + op + " on a secret can be fooled by type juggling and timing; "
                                + "use hash_equals() for secrets, or === and !==.")
    }

    /// Reports whether an expression's name suggests a secret, such as `$token` or `$user->passwordHash`.
    ///
    /// - Parameter node: One side of a comparison.
    /// - Returns: Whether its variable, property, or callee is named like a hash, token, or secret.
    private func isSecret(_ node: Node) -> Bool {
        let named = Self.namedAccess[node.nodeType ?? ""].flatMap { node.child(byFieldName: $0) }
        let target = node.nodeType == "variable_name" || node.nodeType == "subscript_expression" ? node : named
        let name = target.flatMap(tree.text) ?? ""
        return name.range(of: Self.secretName, options: .regularExpression) != nil
    }
}
