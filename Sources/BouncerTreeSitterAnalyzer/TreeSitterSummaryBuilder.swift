import SwiftTreeSitter
import BouncerCore
import BouncerRules

/// Walks a tree-sitter parse tree once, collecting everything the AST rules need.
final class TreeSitterSummaryBuilder {
    let spec: TreeSitterLanguageSpec
    private let source: String
    private var functions: [CollectedFunction] = []
    private var types: [CollectedType] = []
    private var switches: [CollectedSwitch] = []
    private var importCount = 0
    private var markers: [CollectedMarker] = []
    private lazy var quality: TreeSitterQualityCollector? = spec.quality.map {
        TreeSitterQualityCollector(spec: spec, quality: $0, text: { [unowned self] in self.text(of: $0) })
    }

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
    func text(of node: Node) -> String? {
        guard let range = Range(node.range, in: source) else { return nil }
        return String(source[range])
    }

    /// Walks the tree from its root and assembles the collected summary.
    ///
    /// - Parameter root: The parse tree's root node.
    /// - Returns: Everything gathered during the walk.
    func build(root: Node) -> DeclarationSummary {
        walk(root)
        return DeclarationSummary(
            functions: functions, types: types, switches: switches, importCount: importCount, markers: markers
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
        if spec.importNodeTypes.contains(type) || isImportCall(node, type: type) { importCount += 1 }
        collectMarkers(node, type: type)
    }

    /// Records every smell this node exhibits, if the language has a quality spec.
    ///
    /// Only named nodes are checked, so a keyword token such as the `number` in `x: number`
    /// isn't mistaken for a number literal.
    ///
    /// - Parameters:
    ///   - node: The node to check.
    ///   - type: Its type, already resolved by the caller.
    private func collectMarkers(_ node: Node, type: String) {
        guard node.isNamed, let quality else { return }
        let here = line(of: node.pointRange.lowerBound)
        markers += quality.markers(at: node, type: type).map { CollectedMarker(kind: $0, line: here) }
        guard let unreachable = quality.unreachableStatement(in: node, type: type) else { return }
        markers.append(CollectedMarker(kind: .unreachableCode, line: line(of: unreachable.pointRange.lowerBound)))
    }

    /// Reports whether a node is a module-loading call such as `require("x")`.
    ///
    /// - Parameters:
    ///   - node: The node to check.
    ///   - type: The node's type, already resolved by the caller.
    /// - Returns: Whether it matches this language's import call, if it has one.
    private func isImportCall(_ node: Node, type: String) -> Bool {
        guard let call = spec.importCall, type == call.nodeType else { return false }
        guard let callee = node.child(byFieldName: "function").flatMap(text) else { return false }
        return call.functionNames.contains(callee)
    }

    /// Collects a function-like node's name, extent, branch count, and doc status.
    ///
    /// - Parameter node: The function/method declaration node.
    private func collectFunction(_ node: Node) {
        guard let body = node.child(byFieldName: "body") else { return }
        functions.append(makeCollectedFunction(node, body: body))
    }

    /// Builds a `CollectedFunction` from a declaration node and its body.
    ///
    /// - Parameters:
    ///   - node: The function/method declaration node.
    ///   - body: Its body block, already resolved by the caller.
    /// - Returns: The collected function.
    private func makeCollectedFunction(_ node: Node, body: Node) -> CollectedFunction {
        let name = functionName(of: node)
        return CollectedFunction(
            name: name, startLine: line(of: node.pointRange.lowerBound), endLine: line(of: node.pointRange.upperBound),
            branchCount: countBranches(in: body), hasDocComment: isDocumented(node),
            visibility: visibility(of: node, name: name), metrics: quality?.metrics(of: node, body: body)
        )
    }

    /// Collects a class node's name, member count, and line span.
    ///
    /// - Parameter node: The class declaration node.
    private func collectType(_ node: Node) {
        guard let body = node.child(byFieldName: "body") else { return }
        let name = node.child(byFieldName: "name").flatMap(text) ?? "<anonymous>"
        let startLine = line(of: node.pointRange.lowerBound), endLine = line(of: node.pointRange.upperBound)
        types.append(CollectedType(
            name: name, memberCount: body.namedChildCount, startLine: startLine, endLine: endLine,
            cohesionGroups: quality.flatMap { $0.cohesionGroups(of: body) }
        ))
    }

    /// Collects a switch/match node's branch count and starting line.
    ///
    /// - Parameter node: The switch/match statement node.
    private func collectSwitch(_ node: Node) {
        let caseCount = countDescendants(of: node, matching: spec.switchBranchNodeTypes)
        switches.append(CollectedSwitch(caseCount: caseCount, startLine: line(of: node.pointRange.lowerBound)))
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
        return op == "&&" || op == "||" || op == "??"
    }

    /// Determines a declaration's access level, per this language's convention.
    ///
    /// - Parameters:
    ///   - node: The declaration node, for conventions that read modifiers or wrappers.
    ///   - name: The declared identifier.
    /// - Returns: The declaration's inferred visibility.
    private func visibility(of node: Node, name: String) -> DeclarationVisibility {
        switch spec.visibilityConvention {
        case .leadingUnderscore: return visibilityByLeadingUnderscore(name)
        case .leadingCase: return (name.first?.isUppercase ?? false) ? .public : .internal
        case .exportKeyword: return visibilityByExport(node, name: name)
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
        case .jsdoc: return hasPrecedingComment(declarationAnchor(of: node), prefix: "/**")
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
    /// - Parameters:
    ///   - node: The declaration node.
    ///   - prefix: Text the comment must start with, such as `/**`, or empty for any comment.
    /// - Returns: Whether an adjacent comment documents it.
    private func hasPrecedingComment(_ node: Node, prefix: String = "") -> Bool {
        guard let previous = node.previousNamedSibling, previous.nodeType == "comment" else { return false }
        guard prefix.isEmpty || (text(of: previous)?.hasPrefix(prefix) ?? false) else { return false }
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
