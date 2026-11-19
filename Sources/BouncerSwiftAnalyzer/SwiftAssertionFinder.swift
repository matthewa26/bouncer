import SwiftSyntax

/// Looks for assertions in a test body: `XCTAssert…`, `XCTFail`, `XCTUnwrap`, `#expect`, `#require`, or a
/// helper whose name starts with `assert`, `expect`, or `verify`.
final class SwiftAssertionFinder: SyntaxVisitor {
    private static let prefixes = ["XCTAssert", "XCTFail", "XCTUnwrap", "assert", "expect", "verify"]
    private var count = 0

    /// Reports whether a body contains an assertion.
    ///
    /// - Parameter body: The test's body.
    /// - Returns: Whether any assertion call or macro appears.
    static func containsAssertion(_ body: CodeBlockSyntax) -> Bool {
        assertionCount(in: body) > 0
    }

    /// Counts a body's assertions, not counting one nested in another's arguments.
    ///
    /// - Parameter body: The test's body.
    /// - Returns: How many assertion calls and macros it makes.
    static func assertionCount(in body: CodeBlockSyntax) -> Int {
        let finder = SwiftAssertionFinder(viewMode: .sourceAccurate)
        finder.walk(body)
        return finder.count
    }

    /// Reports whether a function is a test: an XCTest-style `test…` method or a swift-testing `@Test`.
    ///
    /// - Parameter node: The function declaration.
    /// - Returns: Whether it's a test.
    static func isTest(_ node: FunctionDeclSyntax) -> Bool {
        let hasTestAttribute = node.attributes.contains {
            $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Test"
        }
        let isXCTestMethod = node.name.text.hasPrefix("test") && node.signature.parameterClause.parameters.isEmpty
        return hasTestAttribute || isXCTestMethod
    }

    /// Checks a call's name.
    ///
    /// - Parameter node: The call.
    /// - Returns: `.skipChildren` for an assertion, otherwise `.visitChildren`.
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text ?? ""
        guard Self.prefixes.contains(where: name.hasPrefix) else { return .visitChildren }
        count += 1
        return .skipChildren
    }

    /// Checks a freestanding macro, such as `#expect`.
    ///
    /// - Parameter node: The macro expansion.
    /// - Returns: `.skipChildren` for an assertion, otherwise `.visitChildren`.
    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        guard ["expect", "require"].contains(node.macroName.text) else { return .visitChildren }
        count += 1
        return .skipChildren
    }
}
