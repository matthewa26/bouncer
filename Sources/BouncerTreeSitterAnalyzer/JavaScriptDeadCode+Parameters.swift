import SwiftTreeSitter
import BouncerCore
import BouncerRules

/// Finds TypeScript and JavaScript parameters a function never uses, after the last one it does use
/// (ESLint's `after-used`), since an earlier unused one still holds a callback argument's position.
///
/// Skips empty and throw-only bodies, `override` methods and methods of a class that `extends` or
/// `implements` anything, functions that read `arguments`, destructured and rest parameters, and
/// constructor parameter properties. Signatures without a body, such as overloads and abstract or
/// interface methods, have nothing to check.
struct JavaScriptParameters {
    let tree: DeadCodeTree
    let uses: UseIndex
    private static let functionTypes: Set<String> = [
        "function_declaration", "generator_function_declaration", "function_expression", "function",
        "arrow_function", "method_definition"
    ]
    private static let propertyMarkers: Set<String> = ["accessibility_modifier", "readonly", "override_modifier"]
    private static let nameFields = ["name", "key", "left"]

    /// Lists every checked function's unused trailing parameters.
    ///
    /// - Returns: The unused parameters, in source order.
    func unusedParameters() -> [UnusedDeclaration] {
        var found: [UnusedDeclaration] = []
        TreeWalk.forEach(tree.root) { node in
            guard let type = node.nodeType, Self.functionTypes.contains(type), isChecked(node) else { return }
            found += unused(in: node)
        }
        return found
    }

    /// Reports whether a function's parameters are its own to drop, rather than fixed from outside.
    ///
    /// - Parameter function: The function node.
    /// - Returns: Whether to check it.
    private func isChecked(_ function: Node) -> Bool {
        guard let body = function.child(byFieldName: "body"), !isStub(body) else { return false }
        guard !DeadCodeNodes.childTypes(of: function).contains("override_modifier") else { return false }
        return !inHeritingClass(function) && !uses.isUsed("arguments", within: function.byteRange, except: .max)
    }

    /// Reports whether a body is empty or only throws.
    ///
    /// - Parameter body: The function body; an arrow function's expression body is never a stub.
    /// - Returns: Whether it's a stub.
    private func isStub(_ body: Node) -> Bool {
        guard body.nodeType == "statement_block" else { return false }
        let statements = TreeWalk.namedChildren(body).filter { $0.nodeType != "comment" }
        return statements.isEmpty || (statements.count == 1 && statements[0].nodeType == "throw_statement")
    }

    /// Reports whether a method belongs to a class that extends or implements something.
    ///
    /// - Parameter function: The function node.
    /// - Returns: Whether it may override or implement a fixed signature.
    private func inHeritingClass(_ function: Node) -> Bool {
        guard function.nodeType == "method_definition", let owner = function.parent?.parent else { return false }
        return DeadCodeNodes.childTypes(of: owner).contains("class_heritage")
    }

    /// Lists a function's unused parameters after its last used one.
    ///
    /// - Parameter function: The function node.
    /// - Returns: The unused parameters.
    private func unused(in function: Node) -> [UnusedDeclaration] {
        let parameters = self.parameters(of: function)
        let used = parameters.map { $0.map { isUsed($0, in: function) } ?? true }
        let trailing = (used.lastIndex(of: true) ?? -1) + 1
        let owner = name(of: function)
        return parameters[trailing...].compactMap { identifier in
            guard let identifier, let name = tree.text(identifier), !name.hasPrefix("_") else { return nil }
            return tree.unused(.parameter, name, at: identifier, detail: owner)
        }
    }

    /// Reports whether a parameter is used anywhere in its function besides its own declaration.
    ///
    /// - Parameters:
    ///   - identifier: The parameter's name node.
    ///   - function: The function node.
    /// - Returns: Whether it's used.
    private func isUsed(_ identifier: Node, in function: Node) -> Bool {
        guard let name = tree.text(identifier) else { return true }
        return uses.isUsed(name, within: function.byteRange, except: identifier.byteRange.lowerBound)
    }

    /// Lists a function's parameters by name node, or `nil` for one that can't be checked by name.
    ///
    /// - Parameter function: The function node.
    /// - Returns: One entry per parameter, in order.
    private func parameters(of function: Node) -> [Node?] {
        if let single = function.child(byFieldName: "parameter") { return [single] }
        guard let list = function.child(byFieldName: "parameters") else { return [] }
        return TreeWalk.namedChildren(list).filter { $0.nodeType != "comment" }.map(simpleIdentifier)
    }

    /// Finds the identifier a simple parameter declares, with or without a type or default value.
    ///
    /// - Parameter parameter: One parameter node.
    /// - Returns: Its name node, or `nil` for a pattern, rest, `this`, or parameter-property parameter.
    private func simpleIdentifier(_ parameter: Node) -> Node? {
        let candidate: Node? = switch parameter.nodeType {
        case "identifier": parameter
        case "assignment_pattern": parameter.child(byFieldName: "left")
        case "required_parameter", "optional_parameter":
            isProperty(parameter) ? nil : parameter.child(byFieldName: "pattern")
        default: nil
        }
        return candidate?.nodeType == "identifier" ? candidate : nil
    }

    /// Reports whether a TypeScript constructor parameter is also a property, such as `private x: number`.
    ///
    /// - Parameter parameter: The parameter node.
    /// - Returns: Whether it declares a property, which the class may use outside the constructor.
    private func isProperty(_ parameter: Node) -> Bool {
        !DeadCodeNodes.childTypes(of: parameter).isDisjoint(with: Self.propertyMarkers)
    }

    /// Names a function by its own name, or the variable, key, or member it's bound to.
    ///
    /// - Parameter function: The function node.
    /// - Returns: The name, or `CollectedFunction.anonymousName`.
    private func name(of function: Node) -> String {
        if let name = tree.text(function, field: "name") { return name }
        guard let parent = function.parent else { return CollectedFunction.anonymousName }
        return Self.nameFields.lazy.compactMap { tree.text(parent, field: $0) }.first ?? CollectedFunction.anonymousName
    }
}
