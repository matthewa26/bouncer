import SwiftTreeSitter
import BouncerCore
import BouncerRules

/// Finds Python parameters a function never uses.
///
/// Skips `self`, `cls`, `_`-prefixed names, and `*args`/`**kwargs`; stub bodies (only `pass`, `...`,
/// a docstring, or `raise`); methods of a class with base classes, which may override; functions
/// decorated `abstractmethod`, `overload`, `override`, or `fixture`; `test` functions, whose
/// parameters request pytest fixtures; protocol dunders other than `__init__`, such as `__eq__`;
/// and functions that read `locals()`.
struct PythonParameters {
    let tree: DeadCodeTree
    let uses: UseIndex
    private static let stubStatements: Set<String> = ["pass_statement", "raise_statement", "comment"]
    private static let fixedDecorators = ["abstractmethod", "overload", "override", "fixture"]
    private static let implicitNames: Set<String> = ["self", "cls"]

    /// Lists every checked function's unused parameters.
    ///
    /// - Returns: The unused parameters, in source order.
    func unusedParameters() -> [UnusedDeclaration] {
        var found: [UnusedDeclaration] = []
        TreeWalk.forEach(tree.root) { node in
            guard node.nodeType == "function_definition", let name = tree.text(node, field: "name"),
                  isChecked(node, name: name) else { return }
            found += parameterNames(of: node).filter { !isUsed($0, in: node) }.compactMap { identifier in
                tree.text(identifier).map { tree.unused(.parameter, $0, at: identifier, detail: name) }
            }
        }
        return found
    }

    /// Reports whether a function's parameters are its own to drop, rather than fixed from outside.
    ///
    /// - Parameters:
    ///   - function: The function definition.
    ///   - name: Its name; `test` functions and protocol dunders such as `__eq__` have fixed parameters.
    /// - Returns: Whether to check it.
    private func isChecked(_ function: Node, name: String) -> Bool {
        let isProtocolDunder = name.hasPrefix("__") && name.hasSuffix("__") && name != "__init__"
        guard !name.hasPrefix("test"), !isProtocolDunder else { return false }
        guard let body = function.child(byFieldName: "body"), !isStub(body) else { return false }
        guard !hasFixedDecorator(function), !isMethodOfSubclass(function) else { return false }
        return !uses.isUsed("locals", within: function.byteRange, except: .max)
    }

    /// Reports whether a body only passes, raises, or holds a docstring or `...`.
    ///
    /// - Parameter body: The function body.
    /// - Returns: Whether it's a stub.
    private func isStub(_ body: Node) -> Bool {
        TreeWalk.namedChildren(body).allSatisfy { statement in
            if Self.stubStatements.contains(statement.nodeType ?? "") { return true }
            guard statement.nodeType == "expression_statement", statement.namedChildCount == 1 else { return false }
            return ["string", "ellipsis"].contains(statement.namedChild(at: 0)?.nodeType ?? "")
        }
    }

    /// Reports whether a decorator fixes the function's signature, such as `@abstractmethod`.
    ///
    /// - Parameter function: The function definition.
    /// - Returns: Whether it has such a decorator.
    private func hasFixedDecorator(_ function: Node) -> Bool {
        guard let decorated = function.parent, decorated.nodeType == "decorated_definition" else { return false }
        let decorators = TreeWalk.namedChildren(decorated).filter { $0.nodeType == "decorator" }
        return decorators.compactMap { tree.text($0) }.contains { decorator in
            Self.fixedDecorators.contains { decorator.contains($0) }
        }
    }

    /// Reports whether a function is a method of a class with base classes, so it may override one.
    ///
    /// - Parameter function: The function definition.
    /// - Returns: Whether its class has bases.
    private func isMethodOfSubclass(_ function: Node) -> Bool {
        let owner = DeadCodeNodes.ancestor(of: function) {
            ["class_definition", "function_definition", "module"].contains($0.nodeType ?? "")
        }
        guard let owner, owner.nodeType == "class_definition" else { return false }
        let bases = owner.child(byFieldName: "superclasses")
        return bases.map { $0.namedChildCount > 0 } ?? false
    }

    /// Lists the name node of each plain, typed, or defaulted parameter, skipping `self`, `cls`, and `_x`.
    ///
    /// - Parameter function: The function definition.
    /// - Returns: The parameters' name nodes, in order.
    private func parameterNames(of function: Node) -> [Node] {
        guard let list = function.child(byFieldName: "parameters") else { return [] }
        return TreeWalk.namedChildren(list).compactMap(nameNode).filter { identifier in
            guard let name = tree.text(identifier) else { return false }
            return !name.hasPrefix("_") && !Self.implicitNames.contains(name)
        }
    }

    /// Finds the identifier one parameter declares, with or without a type or default value.
    ///
    /// - Parameter parameter: One parameter node.
    /// - Returns: Its name node, or `nil` for `*args`, `**kwargs`, and the `*` and `/` separators.
    private func nameNode(_ parameter: Node) -> Node? {
        let identifier: Node? = switch parameter.nodeType {
        case "identifier": parameter
        case "typed_parameter": parameter.namedChild(at: 0)
        case "default_parameter", "typed_default_parameter": parameter.child(byFieldName: "name")
        default: nil
        }
        return identifier?.nodeType == "identifier" ? identifier : nil
    }

    /// Reports whether a parameter is used anywhere in its function besides its own declaration.
    ///
    /// - Parameters:
    ///   - identifier: The parameter's name node.
    ///   - function: The function definition.
    /// - Returns: Whether it's used.
    private func isUsed(_ identifier: Node, in function: Node) -> Bool {
        guard let name = tree.text(identifier) else { return true }
        return uses.isUsed(name, within: function.byteRange, except: identifier.byteRange.lowerBound)
    }
}
