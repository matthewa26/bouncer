import Foundation
import BouncerCore

/// One concrete type, or one Swift extension of it, with the project abstractions it claims.
struct ConformingUnit {
    let decl: DeclaredType
    /// Its protocols, interfaces, and abstract classes in the project, following refinements.
    let abstractions: [DeclaredType]
}

/// The project's concrete types and extensions with the abstractions they implement, for
/// `liskov-substitution` and `interface-segregation`.
///
/// A unit is judged when it's concrete (not a protocol, interface, or abstract class), outside test, DocC, and
/// generated files, has no project subclasses, and isn't named `Abstract…` or `Base…`, so intermediate bases
/// that trap to mean "abstract" aren't.
struct Conformances {
    let hierarchy: TypeHierarchy
    /// The judged units, sorted by path and line.
    let units: [ConformingUnit]

    /// Collects the units.
    ///
    /// - Parameter index: The project's facts.
    init(index: ProjectIndex) {
        let hierarchy = TypeHierarchy(index: index)
        self.hierarchy = hierarchy
        let declarations = (hierarchy.types + hierarchy.extensions)
            .sorted { ($0.path, $0.fact.line) < ($1.path, $1.fact.line) }
        units = declarations.filter { Self.isJudged($0, hierarchy: hierarchy, index: index) }.map { decl in
            ConformingUnit(decl: decl, abstractions: Self.abstractions(of: decl, hierarchy: hierarchy))
        }
    }

    /// Lists an abstraction's requirements: a protocol's or interface's methods, or an abstract class's
    /// methods that are empty or only throw.
    ///
    /// - Parameter abstraction: The protocol, interface, or abstract class.
    /// - Returns: The required methods' names, in declaration order, each once.
    static func requirements(of abstraction: DeclaredType) -> [String] {
        let fact = abstraction.fact
        let stubs = Set(fact.allRefused + fact.allEmpty)
        let required = fact.kind == .abstractClass ? fact.methods.filter(stubs.contains) : fact.methods
        return required.reduce(into: []) { list, name in if !list.contains(name) { list.append(name) } }
    }

    /// Lists the methods whose refusal is `refused-bequest`'s: Swift `override`s, and methods a project class
    /// ancestor implements for real.
    ///
    /// - Parameter unit: The type or extension.
    /// - Returns: The methods' names.
    func bequeathed(to unit: ConformingUnit) -> Set<String> {
        let inherited = classDeclaration(of: unit).map(hierarchy.ancestors) ?? []
        let real = inherited.flatMap { ancestor in ancestor.fact.methods.filter { Self.isReal($0, in: ancestor) } }
        return Set(real + unit.decl.fact.overrides)
    }

    /// Lists a class's methods that open with a precondition the nearest project ancestor implementing them
    /// doesn't have.
    ///
    /// - Parameter unit: The type or extension.
    /// - Returns: Each narrowed method as `Parent.method`.
    func narrowedPreconditions(of unit: ConformingUnit) -> [String] {
        guard unit.decl.fact.kind.isClass else { return [] }
        let ancestors = hierarchy.trustedAncestors(of: unit.decl), fact = unit.decl.fact
        let isSwift = unit.decl.path.hasSuffix(".swift")
        return fact.guarded.filter { !isSwift || fact.overrides.contains($0) }.compactMap { name -> String? in
            guard let parent = ancestors.first(where: { $0.fact.methods.contains(name) }),
                  Self.isReal(name, in: parent), !parent.fact.guarded.contains(name) else { return nil }
            return "\(parent.name).\(name)"
        }
    }

    /// Finds the class a unit belongs to: itself, or the type an extension extends.
    ///
    /// - Parameter unit: The type or extension.
    /// - Returns: The class, or `nil` if it isn't one in the project.
    private func classDeclaration(of unit: ConformingUnit) -> DeclaredType? {
        let decl = unit.decl
        let type = decl.fact.kind == .extension ? hierarchy.resolver.resolve(decl.name, from: decl) : decl
        return type.flatMap { $0.fact.kind.isClass ? $0 : nil }
    }

    /// Reports whether a type's method has a real body: neither empty nor only throwing.
    ///
    /// - Parameters:
    ///   - name: The method.
    ///   - type: The type declaring it.
    /// - Returns: Whether its body does something.
    private static func isReal(_ name: String, in type: DeclaredType) -> Bool {
        !type.fact.allRefused.contains(name) && !type.fact.allEmpty.contains(name)
    }

    /// Reports whether a declaration is judged: concrete, outside incidental files, without project
    /// subclasses, and not named like an abstract base.
    ///
    /// - Parameters:
    ///   - decl: The type or extension.
    ///   - hierarchy: The project's types.
    ///   - index: The project's facts.
    /// - Returns: Whether to judge it.
    private static func isJudged(_ decl: DeclaredType, hierarchy: TypeHierarchy, index: ProjectIndex) -> Bool {
        let extended = decl.fact.kind == .extension ? hierarchy.resolver.resolve(decl.name, from: decl) : decl
        let named = decl.name.hasPrefix("Abstract") || decl.name.hasPrefix("Base")
        let concrete = !decl.fact.kind.isAbstract && extended?.fact.kind.isAbstract != true && !named
        let leaf = (hierarchy.children[extended?.id ?? decl.id] ?? []).isEmpty
        return concrete && leaf && !ProjectUnits.isIncidental(decl.path, in: index)
    }

    /// Lists the abstractions a declaration claims, following protocol and abstract-class refinements.
    ///
    /// - Parameters:
    ///   - decl: The type or extension.
    ///   - hierarchy: The project's types.
    /// - Returns: The abstractions, each once, in the order reached.
    static func abstractions(of decl: DeclaredType, hierarchy: TypeHierarchy) -> [DeclaredType] {
        let direct = decl.fact.kind == .extension
            ? decl.fact.supertypes.compactMap { hierarchy.resolver.resolve($0, from: decl) }
            : hierarchy.supertypes[decl.id] ?? []
        return closure(direct, hierarchy: hierarchy)
    }

    /// Follows refinements from a declaration's direct supertypes to every abstraction they reach.
    ///
    /// - Parameters:
    ///   - direct: The direct supertypes.
    ///   - hierarchy: The project's types.
    /// - Returns: The abstractions, each once, in the order reached.
    private static func closure(_ direct: [DeclaredType], hierarchy: TypeHierarchy) -> [DeclaredType] {
        var queue = direct, seen: Set<String> = [], result: [DeclaredType] = []
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard next.fact.kind.isAbstract, seen.insert(next.id).inserted else { continue }
            result.append(next)
            queue += hierarchy.supertypes[next.id] ?? []
        }
        return result
    }
}
