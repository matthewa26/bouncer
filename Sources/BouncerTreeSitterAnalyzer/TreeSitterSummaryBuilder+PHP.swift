import Foundation
import SwiftTreeSitter
import BouncerCore
import BouncerRules

/// PHP's declaration conventions: a method is public unless it says otherwise.
extension TreeSitterSummaryBuilder {
    /// Applies PHP visibility: no modifier or `public` is public, `protected` is internal, and `private` is private.
    /// A free function, closure, or interface method has no modifier, so it's public.
    ///
    /// - Parameter node: The function node.
    /// - Returns: Its visibility.
    func visibilityByAccessModifier(_ node: Node) -> DeclarationVisibility {
        let modifier = TreeWalk.namedChildren(node).first { $0.nodeType == "visibility_modifier" }.flatMap(text)
        switch modifier {
        case "private": return .private
        case "protected": return .internal
        default: return .public
        }
    }
}

/// PHP conventions shared by the quality spec and the PHP smell checks.
enum PHPSyntax {
    /// A path, relative to the repository root, that holds test code: anything under a `tests/` or `test/` folder,
    /// and any `…Test.php` file.
    static let testPathPattern = #"(^|/)[Tt]ests?/|Test\.php$"#

    /// Reports whether a file is test code by its path.
    ///
    /// - Parameter path: The file's path, relative to the repository root.
    /// - Returns: Whether it's under a test folder or named like a PHPUnit test case.
    static func isTestPath(_ path: String) -> Bool {
        path.range(of: testPathPattern, options: .regularExpression) != nil
    }
}
