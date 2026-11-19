import SwiftSyntax
import BouncerRules

/// Measures a Swift type's LCOM4 cohesion from its member block.
enum SwiftCohesion {
    /// Counts how many unrelated groups a type's instance methods split into.
    ///
    /// - Parameter members: The type's member block.
    /// - Returns: The LCOM4 group count, per `CohesionGraph`.
    static func groupCount(of members: MemberBlockSyntax) -> Int {
        let methods = members.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }.filter { !isStatic($0) }
        let memberNames = Set(methods.map(\.name.text)).union(propertyNames(in: members))
        return CohesionGraph.groupCount(methods.map {
            CohesionGraph.Method(name: $0.name.text, references: references(in: $0, to: memberNames))
        })
    }

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

    /// Lists the names of a type's instance properties.
    ///
    /// - Parameter members: The type's member block.
    /// - Returns: Every property name declared in it.
    private static func propertyNames(in members: MemberBlockSyntax) -> Set<String> {
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
    private static func references(in method: FunctionDeclSyntax, to memberNames: Set<String>) -> Set<String> {
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
