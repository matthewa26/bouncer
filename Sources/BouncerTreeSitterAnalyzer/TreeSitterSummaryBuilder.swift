import SwiftTreeSitter
import BouncerCore
import BouncerRules

/// Walks a tree-sitter parse tree once, collecting everything the AST rules need.
final class TreeSitterSummaryBuilder {
    let spec: TreeSitterLanguageSpec
    private let source: String
    /// The file's path, relative to the repository root where known, for the languages whose tests are told
    /// apart by where they live.
    private let path: String
    private var functions: [CollectedFunction] = []
    private var types: [CollectedType] = []
    private var switches: [CollectedSwitch] = []
    private var importCount = 0
    private var markers: [CollectedMarker] = []
    private var names: [CollectedName] = []
    private var strings: [CollectedString] = []
    /// Members that `impl`-style blocks add to each type name, merged into that type once the walk is done.
    var extensionMembers: [String: Int] = [:]
    lazy var quality: TreeSitterQualityCollector? = spec.quality.map {
        TreeSitterQualityCollector(spec: spec, quality: $0, text: { [unowned self] in self.text(of: $0) })
    }

    /// Creates a summary builder for a given language's node-type conventions.
    ///
    /// - Parameters:
    ///   - spec: The language's tree-sitter node types and conventions.
    ///   - source: The file's full text, used to extract node text by range.
    ///   - path: The file's path, relative to the repository root where known.
    init(spec: TreeSitterLanguageSpec, source: String, path: String = "") {
        self.spec = spec
        self.source = source
        self.path = path
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
    /// - Parameters:
    ///   - root: The parse tree's root node.
    ///   - unused: The file's unused declarations, from the language's `DeadCodeExtractor`.
    /// - Returns: Everything gathered during the walk.
    func build(root: Node, unused: [UnusedDeclaration] = []) -> DeclarationSummary {
        quality?.moduleNames = importedNames(in: root)
        quality?.filePath = path
        walk(root)
        let shapes = collectShapes(root)
        return DeclarationSummary(
            functions: functions, types: types.map(withExtensionMembers), switches: switches, importCount: importCount,
            markers: markers + (shapes?.markers ?? []), declaredNames: names, stringLiterals: strings,
            unusedDeclarations: unused, shapes: shapes?.facts ?? ShapeFacts()
        )
    }

    /// Collects the size rules' facts with a separate walk, if the language has a quality spec.
    ///
    /// - Parameter root: The parse tree's root node.
    /// - Returns: The size markers and shape facts, or `nil` without a quality spec.
    private func collectShapes(_ root: Node) -> (markers: [CollectedMarker], facts: ShapeFacts)? {
        let namingParents = Set(spec.nameSourceParents.keys)
        return quality.map {
            TreeSitterShapeCollector(spec: $0.quality.shapes, namingParents: namingParents, text: text).collect(root)
        }
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
        if let field = spec.typeExtensionNodeTypes[type] { collectExtension(node, typeField: field) }
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
        if let unreachable = quality.unreachableStatement(in: node, type: type) {
            markers.append(CollectedMarker(kind: .unreachableCode, line: line(of: unreachable.pointRange.lowerBound)))
        }
        collectConventionFacts(node, type: type, quality: quality)
    }

    /// Records the convention rules' facts at one node: markers, declared names, and string literals.
    ///
    /// - Parameters:
    ///   - node: The node to check.
    ///   - type: Its type.
    ///   - quality: The language's quality collector.
    private func collectConventionFacts(_ node: Node, type: String, quality: TreeSitterQualityCollector) {
        markers += quality.conventionMarkers(at: node, type: type).map {
            CollectedMarker(kind: $0.kind, line: line(of: $0.at.pointRange.lowerBound), value: $0.value)
        }
        collectNameAndString(node, type: type, line: line(of: node.pointRange.lowerBound), quality: quality)
    }


    /// Records a node's declared name or string literal, if it's either.
    ///
    /// - Parameters:
    ///   - node: The node to check.
    ///   - type: Its type.
    ///   - line: Its 1-indexed line.
    ///   - quality: The language's quality collector.
    private func collectNameAndString(_ node: Node, type: String, line: Int, quality: TreeSitterQualityCollector) {
        if let name = quality.declaredName(node, type: type) { names.append(CollectedName(name: name, line: line)) }
        if let string = quality.stringLiteral(node, type: type) {
            strings.append(CollectedString(text: string, line: line))
        }
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
        guard let body = functionBody(of: node) else { return }
        var function = makeCollectedFunction(node, body: body)
        function.isObjectKey = isObjectKey(node)
        functions.append(function)
        if quality?.isTestWithoutAssertions(node, name: function.name) == true {
            markers.append(CollectedMarker(kind: .testWithoutAssertions, line: function.startLine))
        }
    }

    /// Builds a `CollectedFunction` from a declaration node and its body.
    ///
    /// - Parameters:
    ///   - node: The function/method declaration node.
    ///   - body: Its body block, already resolved by the caller.
    /// - Returns: The collected function.
    private func makeCollectedFunction(_ node: Node, body: Node) -> CollectedFunction {
        let name = functionName(of: node), start = line(of: node.pointRange.lowerBound)
        return CollectedFunction(
            name: name, startLine: start, endLine: line(of: node.pointRange.upperBound),
            branchCount: countBranches(in: body), hasDocComment: isDocumented(node),
            visibility: visibility(of: node, name: name), metrics: quality?.metrics(of: node, body: body, name: name),
            documentation: documentationFacts(of: node, body: body),
            parameters: quality?.typedParameters(of: node, line: start) ?? []
        )
    }

    /// Collects a class node's name, member count, and line span.
    ///
    /// - Parameter node: The class declaration node.
    private func collectType(_ node: Node) {
        guard let body = typeBody(of: node) else { return }
        types.append(makeCollectedType(node, body: body))
    }

    /// Builds a `CollectedType` from a class node and its body.
    ///
    /// - Parameters:
    ///   - node: The class declaration node.
    ///   - body: Its body, already resolved by the caller.
    /// - Returns: The collected type.
    private func makeCollectedType(_ node: Node, body: Node) -> CollectedType {
        let name = typeName(of: node)
        let startLine = line(of: node.pointRange.lowerBound), endLine = line(of: node.pointRange.upperBound)
        let structure = quality.flatMap { $0.structure(of: node, body: body) { self.countBranches(in: $0) + 1 } }
        let design = quality?.design(of: node, body: body) { self.line(of: $0.pointRange.lowerBound) }
        return CollectedType(
            name: name, memberCount: memberCount(of: body), startLine: startLine, endLine: endLine,
            cohesionGroups: structure.map { CohesionGraph.groupCount($0.methods) },
            shape: quality.flatMap { $0.shape(of: body) }, structure: structure, design: design
        )
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
    func countBranches(in node: Node) -> Int {
        var count = 0
        for index in 0..<node.childCount {
            guard let child = node.child(at: index), let type = child.nodeType else { continue }
            if spec.decisionNodeTypes.contains(type) { count += 1 }
            if type == spec.logicalOperatorNodeType, isLogicalOperator(child) { count += 1 }
            count += countBranches(in: child)
        }
        return count
    }

    /// Reports whether a binary-expression-like node is a logical operator: `&&`, `||`, `??`, or one of the
    /// language's own, such as PHP's `and` and `or`.
    ///
    /// - Parameter node: The node to check.
    /// - Returns: Whether its `operator` field is a logical operator.
    private func isLogicalOperator(_ node: Node) -> Bool {
        guard let op = node.child(byFieldName: "operator").flatMap(text) else { return false }
        let own = spec.quality?.complexity.logicalOperators ?? []
        return op == "&&" || op == "||" || op == "??" || own.contains(op)
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

    /// Checks whether a function's first body statement is a string literal (a docstring).
    ///
    /// - Parameter node: The function declaration node.
    /// - Returns: Whether the body opens with a docstring.
    func hasDocstring(_ node: Node) -> Bool {
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
    func hasPrecedingComment(_ node: Node, prefix: String = "") -> Bool {
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
