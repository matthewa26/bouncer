import SwiftTreeSitter
import BouncerCore

/// Objective-C: each `#import`/`#include` and `@import`, for the project pass's dependency graph.
///
/// Specifiers keep the form that tells the resolver how to look them up: a quoted header as its path
/// (`Foo.h`), a system or framework header in angle brackets (`<UIKit/UIKit.h>`), and a module import
/// with its `@import` keyword (`@import Foundation`).
struct ObjCModuleFacts: ModuleFactsExtractor {
    /// Extracts Objective-C imports and structure.
    ///
    /// - Parameters:
    ///   - root: The parse tree's root.
    ///   - text: Reads a node's source text.
    /// - Returns: The file's imports and declared types; Objective-C has no explicit exports.
    func facts(root: Node, text: (Node) -> String?) -> ModuleFacts {
        var imports: [ImportFact] = []
        TreeWalk.forEach(root) { node in
            guard let specifier = Self.specifier(of: node, text: text) else { return }
            imports.append(ImportFact(specifier: specifier, line: TreeWalk.line(node)))
        }
        return ModuleFacts(imports: imports, structure: TreeWalk.structure(ObjCStructure.self, root: root, text: text))
    }

    /// Reads the specifier one node imports, if it's an import.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - text: Reads a node's source text.
    /// - Returns: `Foo.h`, `<Module/Foo.h>`, or `@import Module`, or `nil` for anything else.
    static func specifier(of node: Node, text: (Node) -> String?) -> String? {
        guard let path = node.child(byFieldName: "path"), let written = text(path) else { return nil }
        switch node.nodeType {
        case "module_import": return "@import " + written
        case "preproc_include": return path.nodeType == "string_literal" ? TreeWalk.unquote(written) : written
        default: return nil
        }
    }
}

/// Collects Objective-C structure facts: classes and protocols from `@interface`/`@protocol` (a category
/// is an extension of its class), with their superclass, adopted protocols, properties, and declared
/// methods; and C functions and `@implementation` methods with their parameters.
final class ObjCStructure: StructureCollector {
    /// The node type of a plain name, such as a class, protocol, or parameter name.
    private static let identifier = "identifier"

    /// Records a declaration by its node type.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - owner: The enclosing `@implementation`'s class, if any.
    /// - Returns: The class an `@implementation` opens, for its methods; otherwise `owner`.
    override func record(_ node: Node, owner: String?) -> String? {
        switch node.nodeType {
        case "class_interface", "protocol_declaration": recordType(node)
        case "class_implementation": return firstIdentifier(node)
        case "function_definition", "method_definition":
            recordFunction(node, owner: node.nodeType == "method_definition" ? owner : nil)
        case "switch_statement": addSwitch(node.child(byFieldName: "condition"), node)
        default: break
        }
        return owner
    }

    /// Records a class, category, or protocol with its supertypes, properties, and declared methods.
    ///
    /// - Parameter node: The `@interface` or `@protocol`.
    private func recordType(_ node: Node) {
        guard let name = firstIdentifier(node) else { return }
        let members = TreeWalk.namedChildren(node)
        let protocols = members.filter { ["parameterized_arguments", "protocol_reference_list"].contains($0.nodeType) }
            .flatMap(protocolNames)
        var facts = TypeMembers(supertypes: [field(node, "superclass")].compactMap { $0 } + protocols)
        facts.fields = members.filter { $0.nodeType == "property_declaration" }.compactMap(propertyName)
        facts.methods = members.filter { $0.nodeType == "method_declaration" }.compactMap(selector)
        add(TypeFact(name: name, line: TreeWalk.line(node), kind: kind(of: node), members: facts))
    }

    /// Classifies an `@interface` or `@protocol`: a category or class extension extends its class.
    ///
    /// - Parameter node: The declaration.
    /// - Returns: `.protocol`, `.extension`, or `.class`.
    private func kind(of node: Node) -> TypeKind {
        if node.nodeType == "protocol_declaration" { return .protocol }
        return node.child(byFieldName: "category") == nil ? .class : .extension
    }

    /// Records a C function or method with its parameter names.
    ///
    /// - Parameters:
    ///   - node: The function or method definition.
    ///   - owner: The method's class, or `nil` for a C function.
    private func recordFunction(_ node: Node, owner: String?) {
        let spec = TreeSitterLanguageSpec.objcDeclarations
        let parameters = (spec.parameters(of: node) ?? []).compactMap { parameter in
            TreeWalk.namedChildren(parameter).last { $0.nodeType == Self.identifier }.flatMap(text)
        }
        addFunction(spec.name(of: node, text: text), node, parameters: parameters, owner: owner)
    }

    /// Reads a method declaration's selector, such as `foo:bar:`.
    ///
    /// - Parameter node: The method declaration.
    /// - Returns: The selector.
    private func selector(_ node: Node) -> String? {
        TreeSitterLanguageSpec.objcDeclarations.name(of: node, text: text)
    }

    /// Lists the protocol names in a `<NSCopying, NSCoding>` list.
    ///
    /// - Parameter list: The list node.
    /// - Returns: The names.
    private func protocolNames(_ list: Node) -> [String] {
        var names: [String] = []
        TreeWalk.forEach(list) { node in
            guard node.nodeType == Self.identifier || node.nodeType == "type_identifier" else { return }
            text(node).map { names.append($0) }
        }
        return names
    }

    /// Reads a property's name, the identifier its declarator ends in.
    ///
    /// - Parameter property: The property declaration.
    /// - Returns: The name.
    private func propertyName(_ property: Node) -> String? {
        var name: String?
        TreeWalk.forEach(property) { node in
            if node.nodeType == Self.identifier, node.parent?.nodeType != "property_attribute" { name = text(node) }
        }
        return name
    }

    /// Reads a declaration's first identifier child: the class or protocol it names.
    ///
    /// - Parameter node: The declaration.
    /// - Returns: The name.
    private func firstIdentifier(_ node: Node) -> String? {
        TreeWalk.namedChildren(node).first { $0.nodeType == Self.identifier }.flatMap(text)
    }
}
