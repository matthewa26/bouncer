import SwiftTreeSitter
import BouncerCore

/// Gathers one file's structure facts during a walk of its parse tree; each language's collector
/// subclasses it with its grammar's node types.
class StructureCollector {
    private var types: [TypeFact] = []
    private var functions: [FunctionFact] = []
    private var switches: [SwitchFact] = []
    /// Reads a node's source text.
    let text: (Node) -> String?

    /// Creates a collector.
    ///
    /// - Parameter text: Reads a node's source text; it must stay valid until `collect(_:)` returns.
    required init(text: @escaping (Node) -> String?) {
        self.text = text
    }

    /// Walks a tree and returns its facts.
    ///
    /// - Parameter root: The parse tree's root.
    /// - Returns: The file's types, functions, and `switch` subjects.
    func collect(_ root: Node) -> StructureFacts {
        visit(root, owner: nil)
        let isGenerated = text(root).map(FactText.isGenerated) ?? false
        return StructureFacts(types: types, functions: functions, switches: switches, isGenerated: isGenerated)
    }

    /// Records whatever one node declares, then visits its children.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - owner: The enclosing class's name, if any.
    func visit(_ node: Node, owner: String?) {
        let inner = record(node, owner: owner)
        for child in TreeWalk.namedChildren(node) { visit(child, owner: inner) }
    }

    /// Records one node's declaration; each language overrides this.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - owner: The enclosing class's name, if any.
    /// - Returns: The owner for the node's children: the node's own name if it's a class, else `owner`.
    func record(_ node: Node, owner: String?) -> String? { owner }

    /// Adds a type.
    ///
    /// - Parameter type: The type.
    func add(_ type: TypeFact) { types.append(type) }

    /// Adds a function.
    ///
    /// - Parameters:
    ///   - name: The function's name, or `nil` for an anonymous one, which is skipped.
    ///   - node: The declaration.
    ///   - parameters: Its parameters.
    func addFunction(_ name: String?, _ node: Node, parameters: [String]) {
        guard let name, !name.isEmpty else { return }
        functions.append(FunctionFact(name: name, line: TreeWalk.line(node), parameters: parameters))
    }

    /// Adds a `switch` subject, unless it's trivial.
    ///
    /// - Parameters:
    ///   - subject: The subject's node.
    ///   - node: The statement.
    ///   - suffix: Text appended to the subject, such as `.(type)` for a Go type switch.
    func addSwitch(_ subject: Node?, _ node: Node, suffix: String = "") {
        guard let written = subject.flatMap(text), let normalized = FactText.subject(written + suffix) else { return }
        switches.append(SwitchFact(subject: normalized, line: TreeWalk.line(node), cases: caseLabels(of: node)))
    }

    /// Reads a `switch` statement's case labels: the text between `case` and `:` in each case clause that
    /// is the statement's child or grandchild, split at commas.
    ///
    /// - Parameter node: The statement.
    /// - Returns: The normalized labels.
    private func caseLabels(of node: Node) -> [String] {
        let clauses = TreeWalk.namedChildren(node).flatMap { [$0] + TreeWalk.namedChildren($0) }
            .filter { ["switch_case", "case_clause", "expression_case", "type_case"].contains($0.nodeType) }
        return clauses.compactMap(text).flatMap { clause -> [String] in
            let head = clause.dropFirst(clause.hasPrefix("case") ? "case".count : 0).prefix { $0 != ":" }
            return head.split(separator: ",").compactMap { FactText.caseLabel(String($0)) }
        }
    }

    /// Reads a named field's text.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - field: The field's name.
    /// - Returns: The field's text, if present.
    func field(_ node: Node, _ field: String) -> String? {
        node.child(byFieldName: field).flatMap(text)
    }

    /// Reads a type annotation's text without its leading `:`.
    ///
    /// - Parameter node: The annotation, or `nil`.
    /// - Returns: The type, or `nil`.
    func annotation(_ node: Node?) -> String? {
        node.flatMap(text).map { String($0.drop { $0 == ":" || $0.isWhitespace }) }
    }

    /// Classifies a method body: empty, only throwing, or neither.
    ///
    /// - Parameters:
    ///   - statements: The body's statements, without comments or docstrings.
    ///   - throwType: The grammar's throw (or raise) statement type.
    ///   - noOps: Statement types that do nothing, such as Python's `pass`.
    /// - Returns: `.empty`, `.refused`, or `nil`.
    static func classify(_ statements: [Node], throwType: String, noOps: Set<String> = []) -> MethodBody? {
        if statements.allSatisfy({ noOps.contains($0.nodeType ?? "") }) { return .empty }
        return statements.count == 1 && statements.first?.nodeType == throwType ? .refused : nil
    }

    /// Notes a method's name and whether its body is empty or only throws.
    ///
    /// - Parameters:
    ///   - name: The method's name.
    ///   - body: Its classification.
    ///   - members: The class's members so far.
    static func addMethod(_ name: String, body: MethodBody?, to members: inout TypeMembers) {
        members.methods.append(name)
        if body == .empty { members.empty.append(name) }
        if body == .refused { members.refused.append(name) }
    }
}

/// A method body that does nothing useful.
enum MethodBody {
    case empty, refused
}
