import SwiftSyntax
import BouncerRules

/// Reads a Swift type's members for its shape and its method-field graph, from which `SwiftTypeStructure`
/// builds LCOM4 and the other cohesion measures.
enum SwiftCohesion {
    /// Counts a type's methods (excluding initializers) and stored properties.
    ///
    /// - Parameters:
    ///   - members: The type's member block.
    ///   - isClass: Whether the type is a class.
    /// - Returns: The type's shape.
    static func shape(of members: MemberBlockSyntax, isClass: Bool) -> TypeShape {
        let methods = members.members.filter { $0.decl.is(FunctionDeclSyntax.self) }.count
        let variables = members.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }
        let stored = variables.flatMap(\.bindings).filter { $0.accessorBlock == nil }.count
        return TypeShape(methodCount: methods, fieldCount: stored, isClass: isClass)
    }

    /// Lists a type's instance methods, leaving out `static` and `class` ones.
    ///
    /// - Parameter members: The type's member block.
    /// - Returns: The methods, in order.
    static func instanceMethods(in members: MemberBlockSyntax) -> [FunctionDeclSyntax] {
        members.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }.filter { !isStatic($0) }
    }

    /// Lists the names of a type's instance methods and properties.
    ///
    /// - Parameter members: The type's member block.
    /// - Returns: Every member name a method could reference.
    static func memberNames(_ members: MemberBlockSyntax) -> Set<String> {
        Set(instanceMethods(in: members).map(\.name.text)).union(propertyNames(in: members))
    }

    /// Lists the names of a type's properties.
    ///
    /// - Parameter members: The type's member block.
    /// - Returns: Every property name declared in it.
    static func propertyNames(in members: MemberBlockSyntax) -> Set<String> {
        let variables = members.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }
        let patterns = variables.flatMap { $0.bindings.map(\.pattern) }
        return Set(patterns.compactMap { $0.as(IdentifierPatternSyntax.self)?.identifier.text })
    }

    /// Collects which of a type's member names a method's body mentions.
    ///
    /// - Parameters:
    ///   - method: The method.
    ///   - memberNames: The type's property and method names.
    /// - Returns: The member names it uses, with or without `self.`.
    static func references(in method: FunctionDeclSyntax, to memberNames: Set<String>) -> Set<String> {
        guard let body = method.body else { return [] }
        let collector = ReferenceCollector(viewMode: .sourceAccurate)
        collector.walk(body)
        return collector.names.intersection(memberNames)
    }

    /// Reports whether a method is `static` or `class`, which LCOM4 leaves out.
    ///
    /// - Parameter method: The method.
    /// - Returns: Whether it's a type method rather than an instance method.
    private static func isStatic(_ method: FunctionDeclSyntax) -> Bool {
        method.modifiers.contains { [.keyword(.static), .keyword(.class)].contains($0.name.tokenKind) }
    }

    /// Gathers every identifier a body references, including the member in `self.name`.
    private final class ReferenceCollector: SyntaxVisitor {
        private(set) var names: Set<String> = []

        /// Records a referenced name.
        ///
        /// - Parameter node: The reference.
        /// - Returns: `.visitChildren`.
        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            names.insert(node.baseName.text)
            return .visitChildren
        }
    }
}
