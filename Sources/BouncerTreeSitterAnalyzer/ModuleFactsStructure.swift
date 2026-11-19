import SwiftTreeSitter
import BouncerCore

/// Gathers one file's structure facts during a walk of its parse tree; each language's collector
/// subclasses it with its grammar's node types.
class StructureCollector {
    private var types: [TypeFact] = []
    private var functions: [FunctionFact] = []
    private var switches: [SwitchFact] = []
    private var builders: [String: CollaborationBuilder] = [:]
    private var builderOrder: [String] = []
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
        return StructureFacts(
            types: types, functions: functions, switches: switches,
            collaborations: builderOrder.compactMap { builders[$0]?.fact }, isGenerated: isGenerated
        )
    }

    /// Records whatever one node declares, notes what it does with other types, then visits its children.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - owner: The enclosing class's name, if any.
    func visit(_ node: Node, owner: String?) {
        let inner = record(node, owner: owner)
        if let inner, let builder = builders[inner] { collaborate(node, builder) }
        for child in TreeWalk.namedChildren(node) { visit(child, owner: inner) }
    }

    /// Records one node's declaration; each language overrides this.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - owner: The enclosing class's name, if any.
    /// - Returns: The owner for the node's children: the node's own name if it's a class, else `owner`.
    func record(_ node: Node, owner: String?) -> String? { owner }

    /// Notes what one node inside a class does with other types; each language overrides this.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - builder: The enclosing class's collaboration facts.
    func collaborate(_ node: Node, _ builder: CollaborationBuilder) {}

    /// Adds a type, and starts gathering a class's collaboration facts.
    ///
    /// - Parameter type: The type.
    func add(_ type: TypeFact) {
        types.append(type)
        guard type.kind.isClass, builders[type.name] == nil else { return }
        builders[type.name] = CollaborationBuilder(owner: type.name, line: type.line)
        builderOrder.append(type.name)
    }

    /// Adds a function.
    ///
    /// - Parameters:
    ///   - name: The function's name, or `nil` for an anonymous one, which is skipped.
    ///   - node: The declaration.
    ///   - parameters: Its parameters.
    ///   - owner: The type it's a method of, if any.
    ///   - returns: Its written return type, if any.
    func addFunction(
        _ name: String?, _ node: Node, parameters: [String], owner: String? = nil, returns: String? = nil
    ) {
        guard let name, !name.isEmpty else { return }
        functions.append(FunctionFact(
            name: name, line: TreeWalk.line(node), parameters: parameters, owner: owner, returns: returns
        ))
    }

    /// Reports whether a statement is a precondition on the arguments: an `if` testing a parameter whose
    /// consequence only throws (or raises).
    ///
    /// - Parameters:
    ///   - statement: A body's first statement.
    ///   - throwType: The grammar's throw (or raise) statement type.
    ///   - arguments: The method's parameter names.
    /// - Returns: Whether it narrows what the method accepts.
    func isArgumentGuard(_ statement: Node, throwType: String, arguments: Set<String>) -> Bool {
        guard statement.nodeType == "if_statement", statement.child(byFieldName: "alternative") == nil,
              let consequence = statement.child(byFieldName: "consequence"),
              FactText.mentions(field(statement, "condition") ?? "", anyOf: arguments) else { return false }
        let inner = TreeWalk.namedChildren(consequence).filter { $0.nodeType != "comment" }
        return consequence.nodeType == throwType || (inner.count == 1 && inner.first?.nodeType == throwType)
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

    /// Reports whether a method name is private by convention (`_name` or `#name`, but not `__name__`), so not
    /// part of what a subclass promises.
    ///
    /// - Parameter name: The method's name.
    /// - Returns: Whether it's private.
    static func isPrivate(_ name: String) -> Bool {
        name.hasPrefix("#") || (name.hasPrefix("_") && !(name.hasPrefix("__") && name.hasSuffix("__")))
    }

    /// Notes a method's name, whether its body is empty or only throws, and whether it opens with a
    /// precondition.
    ///
    /// - Parameters:
    ///   - name: The method's name.
    ///   - body: Its classification.
    ///   - members: The class's members so far.
    ///   - guarded: Whether its body opens with a precondition before more code.
    static func addMethod(_ name: String, body: MethodBody?, to members: inout TypeMembers, guarded: Bool = false) {
        members.methods.append(name)
        if body == .empty { members.empty.append(name) }
        if body == .refused { members.refused.append(name) }
        if guarded { members.guarded.append(name) }
    }
}

/// A method body that does nothing useful.
enum MethodBody {
    case empty, refused
}
