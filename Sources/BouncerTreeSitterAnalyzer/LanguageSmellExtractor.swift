import SwiftTreeSitter
import BouncerCore

/// A parsed file, with what a smell extractor needs to report on it.
struct SmellTree {
    let root: Node
    let file: SourceFile
    let context: AnalysisContext

    /// Reads a node's source text.
    ///
    /// - Parameter node: The node.
    /// - Returns: Its text, or `nil` if its range doesn't map onto the file.
    func text(of node: Node) -> String? {
        Range(node.range, in: file.contents).map { String(file.contents[$0]) }
    }

    /// Builds a finding at a node's first line, at the rule's configured severity.
    ///
    /// - Parameters:
    ///   - ruleID: The rule reporting it.
    ///   - node: Where it's found.
    ///   - message: What's wrong.
    /// - Returns: The finding, or `nil` if the rule is disabled.
    func finding(_ ruleID: String, at node: Node, _ message: String) -> Finding? {
        let settings = context.settings(for: ruleID)
        guard settings.enabled else { return nil }
        return Finding(
            ruleID: ruleID, severity: settings.severity, filePath: file.path, line: TreeWalk.line(node),
            message: message
        )
    }
}

/// Finds one language's own smells, the ones that need a node's surroundings to judge (test code, comments,
/// a whole call chain), in a single pass over a file's tree.
protocol LanguageSmellExtractor: Sendable {
    /// Lists a file's smells.
    ///
    /// - Parameter tree: The parsed file.
    /// - Returns: One finding per smell whose rule is enabled.
    func findings(in tree: SmellTree) -> [Finding]
}
