import SwiftSyntax

/// Looks for an assertion anywhere in a test body: `XCTAssert…`, `XCTFail`, `XCTUnwrap`, `#expect`,
/// `#require`, or a helper whose name starts with `assert`, `expect`, or `verify`.
final class SwiftAssertionFinder: SyntaxVisitor {
    private static let prefixes = ["XCTAssert", "XCTFail", "XCTUnwrap", "assert", "expect", "verify"]
    private var found = false

    /// Reports whether a body contains an assertion.
    ///
    /// - Parameter body: The test's body.
    /// - Returns: Whether any assertion call or macro appears.
    static func containsAssertion(_ body: CodeBlockSyntax) -> Bool {
        let finder = SwiftAssertionFinder(viewMode: .sourceAccurate)
        finder.walk(body)
        return finder.found
    }

    /// Checks a call's name.
    ///
    /// - Parameter node: The call.
    /// - Returns: `.skipChildren` once an assertion is found, otherwise `.visitChildren`.
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text ?? ""
        if Self.prefixes.contains(where: name.hasPrefix) { found = true }
        return found ? .skipChildren : .visitChildren
    }

    /// Checks a freestanding macro, such as `#expect`.
    ///
    /// - Parameter node: The macro expansion.
    /// - Returns: `.skipChildren` once an assertion is found, otherwise `.visitChildren`.
    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        if ["expect", "require"].contains(node.macroName.text) { found = true }
        return found ? .skipChildren : .visitChildren
    }
}
