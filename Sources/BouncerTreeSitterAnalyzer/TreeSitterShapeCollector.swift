import SwiftTreeSitter
import BouncerCore
import BouncerRules

/// Walks a tree-sitter parse tree collecting the size rules' facts: every type's extent, every
/// closure, long boolean chains, generic parameter counts, and every typed name.
///
/// The tree-sitter counterpart of `SwiftShapeCollector`, driven by a language's `ShapeSpec`.
final class TreeSitterShapeCollector {
    private let spec: ShapeSpec
    /// Parents that name a function expression, which `long-function` measures instead.
    private let namingParents: Set<String>
    private let text: (Node) -> String?
    private var markers: [CollectedMarker] = []
    private var types: [DeclaredType] = []
    private var closures: [CollectedClosure] = []
    private var typedNames: [CollectedName] = []
    private var topLevelOthers: [String] = []
    private var seenNames: Set<String> = []
    private let equalityNames: Set<String> = ["__eq__", "equals", "isEqual", "Equal", "Equals"]

    /// Creates a collector for one file.
    ///
    /// - Parameters:
    ///   - spec: The language's shape node types.
    ///   - namingParents: Parent node types that give a function expression a name.
    ///   - text: Reads a node's source text.
    init(spec: ShapeSpec, namingParents: Set<String>, text: @escaping (Node) -> String?) {
        self.spec = spec
        self.namingParents = namingParents
        self.text = text
    }

    /// Walks a whole tree and returns what it found.
    ///
    /// - Parameter root: The parse tree's root.
    /// - Returns: The size markers found, and the file's shape facts.
    func collect(_ root: Node) -> (markers: [CollectedMarker], facts: ShapeFacts) {
        walk(root)
        let facts = ShapeFacts(
            types: types, closures: closures, typedNames: typedNames, topLevelOthers: topLevelOthers
        )
        return (markers, facts)
    }

    /// Visits one node, then recurses into every child.
    ///
    /// - Parameter node: The node to visit.
    private func walk(_ node: Node) {
        if node.isNamed, let type = node.nodeType { visit(node, type: type) }
        for index in 0..<node.childCount {
            guard let child = node.child(at: index) else { continue }
            walk(child)
        }
    }

    /// Records every fact one named node contributes.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - type: Its type.
    private func visit(_ node: Node, type: String) {
        if let field = spec.typeNodeTypes[type] { recordType(node, nameField: field) }
        if spec.closureNodeTypes.contains(type) { recordClosure(node) }
        if spec.exportedOtherNodeTypes.contains(type) { recordExportedOther(node) }
        if let logical = spec.logical { recordChain(node, logical) }
        if let generics = spec.generics, type == generics.listNodeType { recordGenerics(node, generics) }
        spec.names.sources.filter { $0.nodeType == type }.forEach { recordNames(node, source: $0) }
    }

    /// Records a type declaration's extent, nesting, and visibility.
    ///
    /// - Parameters:
    ///   - node: The type declaration.
    ///   - nameField: The field holding its name.
    private func recordType(_ node: Node, nameField: String) {
        guard let name = node.child(byFieldName: nameField).flatMap(text) else { return }
        if let bodies = spec.typeBodyNodeTypes, !bodies.contains(node.child(byFieldName: "type")?.nodeType ?? "") {
            return
        }
        let (isTopLevel, isExported) = placement(of: node)
        types.append(DeclaredType(
            name: name, startLine: line(of: node), endLine: Int(node.pointRange.upperBound.row) + 1,
            isTopLevel: isTopLevel, visibility: visibility(name: name, isExported: isExported)
        ))
    }

    /// Determines a type's visibility: exported is public; in a language with `export`, anything
    /// else is file-private; otherwise a leading underscore is private, as in Python.
    ///
    /// - Parameters:
    ///   - name: The type's name.
    ///   - isExported: Whether an `export` wraps it.
    /// - Returns: Its visibility.
    private func visibility(name: String, isExported: Bool) -> DeclarationVisibility {
        if isExported { return .public }
        return !spec.exportWrapperNodeTypes.isEmpty || name.hasPrefix("_") ? .private : .internal
    }

    /// Finds whether a declaration sits at file scope and whether an `export` wraps it.
    ///
    /// - Parameter node: The declaration.
    /// - Returns: Whether it's top-level, and whether it's exported.
    private func placement(of node: Node) -> (isTopLevel: Bool, isExported: Bool) {
        var anchor = node, isExported = false
        while let parent = anchor.parent, let type = parent.nodeType,
              spec.exportWrapperNodeTypes.contains(type) || spec.transparentWrapperNodeTypes.contains(type) {
            isExported = isExported || spec.exportWrapperNodeTypes.contains(type)
            anchor = parent
        }
        return (spec.rootNodeTypes.contains(anchor.parent?.nodeType ?? ""), isExported)
    }

    /// Records a closure's extent, unless something names it, it's a test-suite block, or it's a
    /// module wrapper.
    ///
    /// - Parameter node: The closure.
    private func recordClosure(_ node: Node) {
        guard !namingParents.contains(node.parent?.nodeType ?? ""), !isSuiteBlock(node),
              !(spec.skipsImmediatelyInvoked && isImmediatelyInvoked(node)) else { return }
        let end = Int(node.pointRange.upperBound.row) + 1
        closures.append(CollectedClosure(startLine: line(of: node), endLine: end))
    }

    /// Reports whether a closure is an argument of a call such as `describe(…)` or `t.Run(…)`.
    ///
    /// - Parameter node: The closure.
    /// - Returns: Whether the call's callee starts or ends with a suite callee.
    private func isSuiteBlock(_ node: Node) -> Bool {
        let callee = node.parent?.parent?.child(byFieldName: "function").flatMap(text)
        let parts = callee?.split(separator: ".").map(String.init) ?? []
        return [parts.first, parts.last].contains { $0.map(spec.suiteCallees.contains) ?? false }
    }

    /// Reports whether a function expression is called where it's written, as in `(function () { … })()`.
    ///
    /// - Parameter node: The function expression.
    /// - Returns: Whether it's, possibly through parentheses, the callee of a call.
    private func isImmediatelyInvoked(_ node: Node) -> Bool {
        var current = node
        while let parent = current.parent, parent.nodeType == "parenthesized_expression" { current = parent }
        guard let call = current.parent, call.nodeType == "call_expression" else { return false }
        return call.child(byFieldName: "function")?.range == current.range
    }

    /// Records an exported top-level function or variable, which shares the file with its types.
    ///
    /// - Parameter node: The declaration.
    private func recordExportedOther(_ node: Node) {
        guard let wrapper = node.parent, spec.exportWrapperNodeTypes.contains(wrapper.nodeType ?? ""),
              spec.rootNodeTypes.contains(wrapper.parent?.nodeType ?? "") else { return }
        let declarator = (0..<node.namedChildCount).compactMap { node.namedChild(at: $0) }
            .first { $0.nodeType == "variable_declarator" }
        let name = (node.child(byFieldName: "name") ?? declarator?.child(byFieldName: "name")).flatMap(text)
        topLevelOthers.append(name ?? "")
    }

    /// Records a generic parameter list's size at its declaration's line.
    ///
    /// - Parameters:
    ///   - node: The generic parameter list.
    ///   - generics: The language's generic node types.
    private func recordGenerics(_ node: Node, _ generics: GenericSpec) {
        let parameters = namedChildren(of: node).filter { $0.nodeType == generics.parameterNodeType }
        let count = generics.groupedNameNodeType.map { nameType in
            parameters.map { max(1, namedChildren(of: $0).filter { $0.nodeType == nameType }.count) }.reduce(0, +)
        } ?? parameters.count
        let declaration = node.parent.map { line(of: $0) } ?? line(of: node)
        markers.append(CollectedMarker(kind: .tooManyGenericParameters, line: declaration, value: count))
    }

    /// Records the outermost `&&`/`||` chain at a node, with its operand count.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - logical: The language's logical node types.
    private func recordChain(_ node: Node, _ logical: LogicalSpec) {
        guard isChain(node, logical), !isNestedOperand(node, logical), !isInEqualityFunction(node) else { return }
        let count = operands(of: node, logical)
        markers.append(CollectedMarker(kind: .longBooleanExpression, line: line(of: node), value: count))
    }

    /// Reports whether a node sits inside an equality implementation (`__eq__`, `equals`), whose
    /// field-by-field chain is the idiom rather than a smell.
    ///
    /// - Parameter node: The node.
    /// - Returns: Whether an enclosing function has an equality name.
    private func isInEqualityFunction(_ node: Node) -> Bool {
        var current = node.parent
        while let parent = current {
            let name = parent.child(byFieldName: "name").flatMap(text) ?? ""
            if equalityNames.contains(name) { return true }
            current = parent.parent
        }
        return false
    }

    /// Reports whether a node is an `&&`/`||` (or `and`/`or`) operation.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - logical: The language's logical node types.
    /// - Returns: Whether it's a logical operation.
    private func isChain(_ node: Node, _ logical: LogicalSpec) -> Bool {
        guard node.nodeType == logical.nodeType else { return false }
        return node.child(byFieldName: "operator").flatMap(text).map(logical.operators.contains) ?? false
    }

    /// Reports whether a logical operation is an operand of an enclosing one, which counts it.
    ///
    /// - Parameters:
    ///   - node: The logical operation.
    ///   - logical: The language's logical node types.
    /// - Returns: Whether, through parentheses and negations, its parent is a logical operation.
    private func isNestedOperand(_ node: Node, _ logical: LogicalSpec) -> Bool {
        let wrappers = [logical.parenthesizedNodeType, logical.negationNodeType]
        var current = node
        while let parent = current.parent, wrappers.contains(parent.nodeType ?? "") { current = parent }
        return current.parent.map { isChain($0, logical) } ?? false
    }

    /// Counts the leaf conditions of a logical chain, through parentheses and negations.
    ///
    /// - Parameters:
    ///   - node: The logical operation.
    ///   - logical: The language's logical node types.
    /// - Returns: The number of operands.
    private func operands(of node: Node, _ logical: LogicalSpec) -> Int {
        ["left", "right"].compactMap { node.child(byFieldName: $0) }.map { operand in
            let inner = unwrapped(operand, logical)
            return isChain(inner, logical) ? operands(of: inner, logical) : 1
        }.reduce(0, +)
    }

    /// Strips parentheses and negations from an operand.
    ///
    /// - Parameters:
    ///   - node: The operand.
    ///   - logical: The language's logical node types.
    /// - Returns: The innermost wrapped expression.
    private func unwrapped(_ node: Node, _ logical: LogicalSpec) -> Node {
        var current = node
        while let next = wrappedOperand(of: current, logical) { current = next }
        return current
    }

    /// Finds the expression a parenthesized or negated node wraps.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - logical: The language's logical node types.
    /// - Returns: The wrapped expression, or `nil` if the node isn't a wrapper.
    private func wrappedOperand(of node: Node, _ logical: LogicalSpec) -> Node? {
        if node.nodeType == logical.parenthesizedNodeType { return node.namedChild(at: 0) }
        guard node.nodeType == logical.negationNodeType else { return nil }
        return node.child(byFieldName: logical.negationOperandField)
    }

    /// Records every name one declaration introduces, with its declared or literal-inferred type.
    ///
    /// - Parameters:
    ///   - node: The declaration.
    ///   - source: How this declaration holds its names, type, and value.
    private func recordNames(_ node: Node, source: NameSource) {
        let names = nameNodes(of: node, field: source.nameField)
        let values = source.valueField.flatMap { node.child(byFieldName: $0) }.map(listItems) ?? []
        let declared = source.typeField.flatMap { node.child(byFieldName: $0) }.flatMap(text)
        for (index, name) in names.enumerated() {
            let value = values.count == names.count ? values[index] : nil
            record(name, typeName: declared ?? value.flatMap(inferredType), isParameter: source.isParameter)
        }
    }

    /// Adds one typed name, skipping receivers and, where assignment doesn't declare, repeats.
    ///
    /// - Parameters:
    ///   - node: The name node.
    ///   - typeName: Its type, if known.
    ///   - isParameter: Whether it's a parameter.
    private func record(_ node: Node, typeName: String?, isParameter: Bool) {
        guard let name = text(node), name != "_", !spec.names.receiverNames.contains(name) else { return }
        let isRepeat = !seenNames.insert(name).inserted
        if isRepeat, spec.names.keepsFirstAssignmentOnly, !isParameter { return }
        typedNames.append(CollectedName(name: name, line: line(of: node), typeName: typeName, isParameter: isParameter))
    }

    /// Finds the name nodes a declaration holds: its name field (or each item of a list there), or
    /// its direct name-typed children.
    ///
    /// - Parameters:
    ///   - node: The declaration.
    ///   - field: The field holding the name, or `nil` for direct children.
    /// - Returns: The name nodes; empty for a destructuring pattern.
    private func nameNodes(of node: Node, field: String?) -> [Node] {
        let candidates = field.map { node.child(byFieldName: $0).map(listItems) ?? [] } ?? namedChildren(of: node)
        return candidates.filter { spec.names.nameNodeTypes.contains($0.nodeType ?? "") }
    }

    /// Expands a list node (`a, b`) into its items, or wraps any other node as a single item.
    ///
    /// - Parameter node: The node.
    /// - Returns: Its items.
    private func listItems(_ node: Node) -> [Node] {
        spec.names.listNodeTypes.contains(node.nodeType ?? "") ? namedChildren(of: node) : [node]
    }

    /// Infers a type from an initial value: a literal, or a constructor call such as `new Map()`.
    ///
    /// - Parameter value: The initial value.
    /// - Returns: The type's name, or `nil` if it isn't obvious.
    private func inferredType(_ value: Node) -> String? {
        let names = spec.names, type = value.nodeType ?? ""
        if let literal = names.literalTypes[type] { return literal }
        guard let field = names.constructorFields[type], let callee = value.child(byFieldName: field).flatMap(text)
        else { return nil }
        guard names.allocatorCallees.contains(callee) else { return callee }
        return value.child(byFieldName: "arguments")?.namedChild(at: 0).flatMap(text)
    }

    /// Lists a node's named children.
    ///
    /// - Parameter node: The node.
    /// - Returns: Its named children, in order.
    private func namedChildren(of node: Node) -> [Node] {
        (0..<node.namedChildCount).compactMap { node.namedChild(at: $0) }
    }

    /// Converts a node's start to its 1-indexed line.
    ///
    /// - Parameter node: The node.
    /// - Returns: Its first line.
    private func line(of node: Node) -> Int {
        Int(node.pointRange.lowerBound.row) + 1
    }
}

extension TreeSitterQualityCollector {
    /// Reads the local variable names one node declares, for `too-many-locals`.
    ///
    /// - Parameters:
    ///   - node: Any node in a function body.
    ///   - type: Its type.
    /// - Returns: The names it declares; a destructuring pattern counts once where the language says so.
    func localNames(of node: Node, type: String) -> [String] {
        let locals = quality.shapes.locals
        guard let entry = locals.declarationNodeTypes[type] else { return [] }
        guard let field = entry else { return identifiers(in: node) }
        guard let target = node.child(byFieldName: field) else { return [] }
        if target.nodeType == "identifier" { return identifiers(in: target, includingSelf: true) }
        if locals.listNodeTypes.contains(target.nodeType ?? "") { return identifiers(in: target) }
        return locals.countsOtherPatternsAsOne ? [text(target) ?? ""] : []
    }

    /// Reads the identifier children of a node, or the node itself.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - includingSelf: Whether to read the node itself rather than its children.
    /// - Returns: The identifier names, except `_`.
    private func identifiers(in node: Node, includingSelf: Bool = false) -> [String] {
        let nodes = includingSelf ? [node] : (0..<node.namedChildCount).compactMap { node.namedChild(at: $0) }
        return nodes.filter { $0.nodeType == "identifier" }.compactMap(text).filter { $0 != "_" }
    }
}
