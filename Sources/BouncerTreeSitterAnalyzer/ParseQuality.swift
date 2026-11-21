import SwiftTreeSitter

/// How much of a parse tree failed, measured per declaration.
///
/// tree-sitter recovers from syntax it doesn't know by wrapping a few tokens in small `ERROR` nodes, so the
/// share of bytes in error stays low even when most declarations are broken. Counting the declarations that
/// contain an error is a steadier signal: an Objective-C++ file breaks at nearly every C++ construct
/// (namespaces, templates, `::`, references), while a plain Objective-C file with one macro the grammar
/// misreads loses only the declaration around it.
enum ParseQuality {
    /// The share of a file's declarations that contain a parse error.
    ///
    /// Declarations are the root's children other than comments and preprocessor lines, with an Objective-C
    /// `@interface` or `@implementation` counted as its members rather than as one declaration.
    ///
    /// - Parameters:
    ///   - root: The parse tree's root.
    ///   - declarations: Where the grammar keeps type members, or `nil` to count top-level nodes only.
    /// - Returns: A share from 0 to 1; 0 for a file with no declarations.
    static func errorShare(of root: Node, declarations: CDeclarationSpec?) -> Double {
        let units = TreeWalk.namedChildren(root).filter(isDeclaration).flatMap { node in
            members(of: node, declarations: declarations)
        }
        guard !units.isEmpty else { return 0 }
        return Double(units.filter(\.hasError).count) / Double(units.count)
    }

    /// Reports whether a top-level node is a declaration rather than a comment or preprocessor line.
    ///
    /// - Parameter node: A child of the root.
    /// - Returns: Whether it counts.
    private static func isDeclaration(_ node: Node) -> Bool {
        let type = node.nodeType ?? ""
        return type != "comment" && !type.hasPrefix("preproc_")
    }

    /// Splits a type into its members, so one broken method counts as one declaration.
    ///
    /// - Parameters:
    ///   - node: A top-level declaration.
    ///   - declarations: Where the grammar keeps type members.
    /// - Returns: The type's members, or the node itself if it isn't a type or declares none.
    private static func members(of node: Node, declarations: CDeclarationSpec?) -> [Node] {
        guard let declarations, declarations.typeNodeTypes.contains(node.nodeType ?? "") else { return [node] }
        let members = declarations.members(of: node)
        return members.isEmpty ? [node] : members
    }
}
