import Foundation
import SwiftTreeSitter
import BouncerRules

/// The convention rules' per-node checks, driven by the language's `ConventionSpec`.
extension TreeSitterQualityCollector {
    private var conventions: ConventionSpec { quality.conventions }

    /// Lists the convention markers at one node: the kind, the node to report at, and any measurement.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - type: Its type.
    /// - Returns: The markers found here; usually none.
    func conventionMarkers(at node: Node, type: String) -> [(kind: MarkerKind, at: Node, value: Int)] {
        var found: [(kind: MarkerKind, at: Node, value: Int)] = []
        if let alternative = elseAfterExit(node, type: type) { found.append((.elseAfterReturn, alternative, 0)) }
        if isMutableGlobal(node, type: type) { found.append((.globalMutableState, node, 0)) }
        if let length = chainLength(node, type: type) { found.append((.longMessageChain, node, length)) }
        return found
    }

    /// Reports whether an `if` has an `else` after a branch that always exits.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - type: Its type.
    /// - Returns: The `else` node to report at, or `nil`.
    func elseAfterExit(_ node: Node, type: String) -> Node? {
        guard type == conventions.ifNodeType, let alternative = node.child(byFieldName: "alternative"),
              let consequence = node.child(byFieldName: "consequence"),
              let last = lastStatement(in: consequence) else { return nil }
        return quality.statements.jumpNodeTypes.contains(last.nodeType ?? "") ? alternative : nil
    }

    /// Reports whether a node declares or opts into mutable global state.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - type: Its type.
    /// - Returns: Whether it's a top-level mutable declaration or a `global` statement.
    func isMutableGlobal(_ node: Node, type: String) -> Bool {
        if conventions.globalStatementNodeTypes.contains(type) { return true }
        guard let keyword = conventions.mutableGlobalNodes[type], isTopLevel(node) else { return false }
        return keyword.map { node.child(at: 0).flatMap(text) == $0 } ?? true
    }

    /// Measures the outermost call chain starting at a node, such as `a.b().c()`.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - type: Its type.
    /// - Returns: The number of calls, or `nil` if this isn't the outermost call of a chain of two or more.
    func chainLength(_ node: Node, type: String) -> Int? {
        guard let chain = conventions.chain, type == chain.callNodeType,
              node.parent?.nodeType != chain.memberNodeType else { return nil }
        var current: Node? = node, count = 0
        while let call = current, call.nodeType == chain.callNodeType {
            count += 1
            let callee = call.child(byFieldName: chain.calleeField)
            current = callee?.nodeType == chain.memberNodeType ? callee?.child(byFieldName: chain.objectField) : nil
        }
        return count > 1 ? count : nil
    }

    /// Reports whether a node is a runtime type check.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - type: Its type.
    /// - Returns: Whether it matches one of the language's type-check forms.
    func isTypeCheck(_ node: Node, type: String) -> Bool {
        conventions.typeChecks.contains { match in
            guard match.nodeType == type else { return false }
            guard let field = match.field else { return true }
            return node.child(byFieldName: field).flatMap(text).map(match.texts.contains) ?? false
        }
    }

    /// Reports whether a function is a test with no assertions in it.
    ///
    /// - Parameters:
    ///   - node: The function node.
    ///   - name: Its resolved name.
    /// - Returns: Whether it's a test that never asserts.
    func isTestWithoutAssertions(_ node: Node, name: String) -> Bool {
        guard let tests = conventions.tests, isTest(node, name: name, tests: tests), let body = text(node) else {
            return false
        }
        return body.range(of: tests.assertionPattern, options: .regularExpression) == nil
    }

    /// Reads the name a declaration introduces, for the naming rules.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - type: Its type.
    /// - Returns: The declared identifier, or `nil` if the node isn't a checked declaration.
    func declaredName(_ node: Node, type: String) -> String? {
        if let field = conventions.nameFields[type], !isLoopVariable(node),
           let name = node.child(byFieldName: field), name.nodeType == "identifier" {
            return text(name)
        }
        let parentType = node.parent?.nodeType ?? ""
        guard type == "identifier", conventions.parameterListTypes.contains(parentType) else { return nil }
        return text(node)
    }

    /// Reads a plain string literal's contents, skipping imports and interpolated strings.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - type: Its type.
    /// - Returns: The literal's text without quotes, or `nil`.
    func stringLiteral(_ node: Node, type: String) -> String? {
        guard conventions.stringNodeTypes.contains(type), !isInImport(node) else { return nil }
        let children = (0..<node.namedChildCount).compactMap { node.namedChild(at: $0) }
        let isInterpolated = children.contains { conventions.interpolationTypes.contains($0.nodeType ?? "") }
        guard !isInterpolated else { return nil }
        return children.filter { conventions.stringContentTypes.contains($0.nodeType ?? "") }.compactMap(text).joined()
    }

    /// Finds a block's last statement, descending into nested statement lists (Go's `block`).
    ///
    /// - Parameter block: The block.
    /// - Returns: Its last non-comment statement.
    private func lastStatement(in block: Node) -> Node? {
        let children = (0..<block.namedChildCount).compactMap { block.namedChild(at: $0) }
        guard let last = children.last(where: { $0.nodeType != "comment" }) else { return nil }
        return quality.statements.blockNodeTypes.contains(last.nodeType ?? "") ? lastStatement(in: last) : last
    }

    /// Reports whether a declaration sits at the top level of the file.
    ///
    /// - Parameter node: The declaration.
    /// - Returns: Whether its parent is the root, possibly through a wrapper like `export`.
    private func isTopLevel(_ node: Node) -> Bool {
        guard let parent = node.parent?.nodeType else { return false }
        if conventions.rootNodeTypes.contains(parent) { return true }
        return conventions.rootWrapperNodeTypes.contains(parent)
            && conventions.rootNodeTypes.contains(node.parent?.parent?.nodeType ?? "")
    }

    /// Reports whether a function is a test, by its name or by being passed to a test-defining call.
    ///
    /// - Parameters:
    ///   - node: The function node.
    ///   - name: Its resolved name.
    ///   - tests: The language's test conventions.
    /// - Returns: Whether it's a test.
    private func isTest(_ node: Node, name: String, tests: TestSpec) -> Bool {
        if let pattern = tests.namePattern, name.range(of: pattern, options: .regularExpression) != nil { return true }
        guard node.parent?.nodeType == "arguments", let call = node.parent?.parent else { return false }
        return call.child(byFieldName: "function").flatMap(text).map(tests.callbackCallees.contains) ?? false
    }

    /// Reports whether a declaration is a loop variable, such as `i` in `for (let i = 0; …)`.
    ///
    /// - Parameter node: The declaration.
    /// - Returns: Whether a loop encloses it within two levels.
    private func isLoopVariable(_ node: Node) -> Bool {
        [node.parent, node.parent?.parent].contains { conventions.loopNodeTypes.contains($0?.nodeType ?? "") }
    }

    /// Reports whether a node sits inside an import or `require` call.
    ///
    /// - Parameter node: The node.
    /// - Returns: Whether an import encloses it.
    private func isInImport(_ node: Node) -> Bool {
        var current = node.parent
        while let parent = current {
            if spec.importNodeTypes.contains(parent.nodeType ?? "") || isImportCall(parent) { return true }
            current = parent.parent
        }
        return false
    }

    /// Reports whether a node is a module-loading call such as `require("x")`.
    ///
    /// - Parameter node: The node.
    /// - Returns: Whether it matches the language's import call.
    private func isImportCall(_ node: Node) -> Bool {
        guard let call = spec.importCall, node.nodeType == call.nodeType else { return false }
        return node.child(byFieldName: "function").flatMap(text).map(call.functionNames.contains) ?? false
    }
}
