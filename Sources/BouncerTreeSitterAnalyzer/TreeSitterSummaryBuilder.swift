import SwiftTreeSitter
import BouncerCore

/// Walks a tree-sitter parse tree once, collecting everything the AST rules need.
final class TreeSitterSummaryBuilder {
    private let spec: TreeSitterLanguageSpec
    private let source: String
    private var functions: [TSCollectedFunction] = []
    private var types: [TSCollectedType] = []
    private var switches: [TSCollectedSwitch] = []
    private var importCount = 0

    /// Creates a summary builder for a given language's node-type conventions.
    ///
    /// - Parameters:
    ///   - spec: The language's tree-sitter node types and conventions.
    ///   - source: The file's full text, used to extract node text by range.
    init(spec: TreeSitterLanguageSpec, source: String) {
        self.spec = spec
        self.source = source
    }

    /// Extracts a node's source text, since this SwiftTreeSitter version has no `Node.text`.
    ///
    /// - Parameter node: The node whose text to extract.
    /// - Returns: The node's text, or `nil` if its range doesn't map onto `source`.
    private func text(of node: Node) -> String? {
        guard let range = Range(node.range, in: source) else { return nil }
        return String(source[range])
    }

    /// Walks the tree from its root and assembles the collected summary.
    ///
    /// - Parameter root: The parse tree's root node.
    /// - Returns: Everything gathered during the walk.
    func build(root: Node) -> TreeSitterDeclarationSummary {
        walk(root)
        return TreeSitterDeclarationSummary(
            functions: functions, types: types, switches: switches, importCount: importCount
        )
    }

    /// Visits one node, then recurses into every child.
    ///
    /// - Parameter node: The node to visit.
    private func walk(_ node: Node) {
        visit(node)
        for index in 0..<node.childCount {
            guard let child = node.child(at: index) else { continue }
            walk(child)
        }
    }

    /// Dispatches one node to the matching collector, based on its type.
    ///
    /// - Parameter node: The node to classify and collect.
    private func visit(_ node: Node) {
        guard let type = node.nodeType else { return }
        if spec.functionNodeTypes.contains(type) { collectFunction(node) }
        if spec.classNodeTypes.contains(type) { collectType(node) }
        if spec.switchNodeTypes.contains(type) { collectSwitch(node) }
        if spec.importNodeTypes.contains(type) { importCount += 1 }
    }

    /// Collects a function-like node's name, extent, branch count, and doc status.
    ///
    /// - Parameter node: The function/method declaration node.
    private func collectFunction(_ node: Node) {
        guard let body = node.child(byFieldName: "body") else { return }
        functions.append(makeCollectedFunction(node, body: body))
    }

    /// Builds a `TSCollectedFunction` from a declaration node and its body.
    ///
    /// - Parameters:
    ///   - node: The function/method declaration node.
    ///   - body: Its body block, already resolved by the caller.
    /// - Returns: The collected function.
    private func makeCollectedFunction(_ node: Node, body: Node) -> TSCollectedFunction {
        let name = node.child(byFieldName: "name").flatMap(text) ?? "<anonymous>"
        return TSCollectedFunction(
            name: name, startLine: line(of: node.pointRange.lowerBound), endLine: line(of: node.pointRange.upperBound),
            branchCount: countBranches(in: body), hasDocComment: isDocumented(node),
            visibility: visibility(ofName: name)
        )
    }

    /// Collects a class node's name, member count, and starting line.
    ///
    /// - Parameter node: The class declaration node.
    private func collectType(_ node: Node) {
        guard let body = node.child(byFieldName: "body") else { return }
        let name = node.child(byFieldName: "name").flatMap(text) ?? "<anonymous>"
        let startLine = line(of: node.pointRange.lowerBound)
        types.append(TSCollectedType(name: name, memberCount: body.namedChildCount, startLine: startLine))
    }

    /// Collects a switch/match node's branch count and starting line.
    ///
    /// - Parameter node: The switch/match statement node.
    private func collectSwitch(_ node: Node) {
        let caseCount = countDescendants(of: node, matching: spec.switchBranchNodeTypes)
        switches.append(TSCollectedSwitch(caseCount: caseCount, startLine: line(of: node.pointRange.lowerBound)))
    }

    /// Counts decision points within a function body, for cyclomatic complexity.
    ///
    /// - Parameter node: The subtree to count within.
    /// - Returns: The number of decision-point nodes found.
    private func countBranches(in node: Node) -> Int {
        var count = 0
        for index in 0..<node.childCount {
            guard let child = node.child(at: index), let type = child.nodeType else { continue }
            if spec.decisionNodeTypes.contains(type) { count += 1 }
            if type == spec.logicalOperatorNodeType, isLogicalOperator(child) { count += 1 }
            count += countBranches(in: child)
        }
        return count
    }

    /// Reports whether a binary-expression-like node is a logical `&&`/`||`.
    ///
    /// - Parameter node: The node to check.
    /// - Returns: Whether its `operator` field is `&&` or `||`.
    private func isLogicalOperator(_ node: Node) -> Bool {
        let op = node.child(byFieldName: "operator").flatMap(text)
        return op == "&&" || op == "||"
    }

    /// Determines a declaration's access level from its name, per this language's convention.
    ///
    /// - Parameter name: The declared identifier.
    /// - Returns: The identifier's inferred visibility.
    private func visibility(ofName name: String) -> DeclarationVisibility {
        switch spec.visibilityConvention {
        case .leadingUnderscore: return visibilityByLeadingUnderscore(name)
        case .leadingCase: return (name.first?.isUppercase ?? false) ? .public : .internal
        }
    }

    /// Applies Python's underscore-prefix naming convention.
    ///
    /// - Parameter name: The declared identifier.
    /// - Returns: `.private` for a double leading underscore, `.internal` for one, else `.public`.
    private func visibilityByLeadingUnderscore(_ name: String) -> DeclarationVisibility {
        if name.hasPrefix("__") && !name.hasSuffix("__") { return .private }
        if name.hasPrefix("_") { return .internal }
        return .public
    }

    /// Counts every descendant matching a set of node types, anywhere within a subtree.
    ///
    /// - Parameters:
    ///   - node: The subtree to search.
    ///   - types: The node types to count.
    /// - Returns: The total number of matching descendants.
    private func countDescendants(of node: Node, matching types: Set<String>) -> Int {
        var count = 0
        for index in 0..<node.childCount {
            guard let child = node.child(at: index) else { continue }
            if let type = child.nodeType, types.contains(type) { count += 1 }
            count += countDescendants(of: child, matching: types)
        }
        return count
    }

    /// Checks whether a declaration is documented, per this language's convention.
    ///
    /// - Parameter node: The function/method declaration node.
    /// - Returns: Whether it counts as documented.
    private func isDocumented(_ node: Node) -> Bool {
        switch spec.documentationStyle {
        case .docstring: return hasDocstring(node)
        case .precedingComment: return hasPrecedingComment(node)
        }
    }

    /// Checks whether a function's first body statement is a string literal (a docstring).
    ///
    /// - Parameter node: The function declaration node.
    /// - Returns: Whether the body opens with a docstring.
    private func hasDocstring(_ node: Node) -> Bool {
        guard let body = node.child(byFieldName: "body"), let first = body.namedChild(at: 0) else { return false }
        guard first.nodeType == "expression_statement" else { return false }
        return first.namedChild(at: 0)?.nodeType == "string"
    }

    /// Checks whether a comment sits directly above a declaration with no blank line gap.
    ///
    /// - Parameter node: The declaration node.
    /// - Returns: Whether an adjacent comment documents it.
    private func hasPrecedingComment(_ node: Node) -> Bool {
        guard let previous = node.previousNamedSibling, previous.nodeType == "comment" else { return false }
        return previous.pointRange.upperBound.row + 1 == node.pointRange.lowerBound.row
    }

    /// Converts a tree-sitter point's 0-indexed row to Bouncer's 1-indexed line number.
    ///
    /// - Parameter point: The point to convert.
    /// - Returns: The 1-indexed line number.
    private func line(of point: Point) -> Int {
        Int(point.row) + 1
    }
}
