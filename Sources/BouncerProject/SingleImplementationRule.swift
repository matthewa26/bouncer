import Foundation
import BouncerCore

/// Flags a protocol or interface with exactly one implementation in the project that isn't a test seam:
/// speculative generality, an abstraction nothing yet needs. Off unless configured.
///
/// Implementations are types declaring the protocol (directly, through an extension, or through a
/// protocol that refines it). A protocol is a test seam, and skipped, when a test file implements it or
/// mentions it. Swift `public` protocols are skipped unless `includePublic` is set, since other packages may
/// implement them, and so are TS/JS interfaces and Python protocols that declare properties, which describe
/// data shapes that object literals satisfy without `implements`, and names following a convention that
/// gives the protocol another purpose: `Any…` (type erasure) and `…Protocol` (the protocol behind a concrete
/// type). Go interfaces are satisfied implicitly, so they never count as implemented. Unused parameters, the
/// other half of speculative generality, are `unused-parameter`'s.
public struct SingleImplementationRule: ProjectRule {
    public let id = "single-implementation-interface"

    /// Creates the rule.
    public init() {}

    /// Flags each protocol or interface with one implementation and no test use.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph and facts.
    ///   - targets: Unused; each finding lands at the protocol.
    ///   - context: Repo-wide state; the rule only runs when configured, with `includePublic`.
    /// - Returns: One finding per single-implementation protocol.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        guard let settings = context.ruleSettings[id], settings.enabled else { return [] }
        let includePublic = settings.parameters.bool("includePublic", default: false)
        let hierarchy = TypeHierarchy(index: index)
        let implementations = Implementations(hierarchy: hierarchy), seams = TestSeams(index: index)
        return hierarchy.types.compactMap { type in
            guard isCandidate(type, index: index, includePublic: includePublic), !seams.contains(type.name),
                  let only = implementations.single(of: type) else { return nil }
            return ProjectFinding.make(id, type.path, type.fact.line, Self.message(type, only), context)
        }
    }

    /// Explains a single-implementation abstraction.
    ///
    /// - Parameters:
    ///   - type: The protocol or interface.
    ///   - only: Its implementation.
    /// - Returns: The message.
    private static func message(_ type: DeclaredType, _ only: DeclaredType) -> String {
        "\(type.fact.kind == .interface ? "Interface" : "Protocol") \"\(type.name)\" has one implementation, "
            + "\"\(only.name)\" (\(only.path)), and no test double; use the type directly until a second "
            + "implementation needs the abstraction."
    }

    /// Reports whether a protocol's name says it exists for a reason other than a second implementation:
    /// `Any…` for type erasure (checking `is AnyOptionGroup` without the generic argument) and `…Protocol` for
    /// the protocol behind a concrete type, used in generic constraints.
    ///
    /// - Parameter name: The protocol's name.
    /// - Returns: Whether it follows one of those conventions.
    private static func isConventional(_ name: String) -> Bool {
        let erased = name.hasPrefix("Any") && name.dropFirst(3).first?.isUppercase == true
        return erased || (name.hasSuffix("Protocol") && name != "Protocol")
    }

    /// Reports whether a type is a protocol or interface this rule judges.
    ///
    /// - Parameters:
    ///   - type: The type.
    ///   - index: The project's facts, for Swift's public declarations.
    ///   - includePublic: Whether Swift `public` protocols are judged.
    /// - Returns: Whether to check it.
    private func isCandidate(_ type: DeclaredType, index: ProjectIndex, includePublic: Bool) -> Bool {
        guard [.protocol, .interface].contains(type.fact.kind), !ProjectUnits.isIncidental(type.path, in: index),
              !Self.isConventional(type.name) else { return false }
        if type.path.hasSuffix(".swift") {
            let exports = index.facts[type.path]?.module.exports ?? []
            return includePublic || !exports.contains { $0.name == type.name && $0.line == type.fact.line }
        }
        return type.fact.fields.isEmpty
    }
}

/// Which concrete types implement each protocol or interface, directly or through a refining protocol.
struct Implementations {
    private let byProtocol: [String: [DeclaredType]]

    /// Collects every concrete type's protocols, including Swift extensions of types outside the project.
    ///
    /// - Parameter hierarchy: The project's types.
    init(hierarchy: TypeHierarchy) {
        let outside = hierarchy.extensions.filter { hierarchy.resolver.resolve($0.name, from: $0) == nil }
        let concrete = hierarchy.types.filter { ![.protocol, .interface].contains($0.fact.kind) } + outside
        let pairs = concrete.flatMap { type in
            Self.closure(Self.direct(type, hierarchy), hierarchy: hierarchy).map { (proto: $0, type: type) }
        }
        byProtocol = Dictionary(grouping: pairs, by: \.proto).mapValues { $0.map(\.type) }
    }

    /// Lists a type's or extension's resolved supertypes.
    ///
    /// - Parameters:
    ///   - type: The type, or an extension of a type outside the project.
    ///   - hierarchy: The project's types.
    /// - Returns: Its supertypes in the project.
    private static func direct(_ type: DeclaredType, _ hierarchy: TypeHierarchy) -> [DeclaredType] {
        guard type.fact.kind == .extension else { return hierarchy.supertypes[type.id] ?? [] }
        return type.fact.supertypes.compactMap { hierarchy.resolver.resolve($0, from: type) }
    }

    /// Returns a protocol's only implementation, if it has exactly one.
    ///
    /// - Parameter type: The protocol or interface.
    /// - Returns: The implementing type, or `nil` for none or several.
    func single(of type: DeclaredType) -> DeclaredType? {
        let implementers = byProtocol[type.id] ?? []
        let distinct = Dictionary(grouping: implementers) { $0.name }
        return distinct.count == 1 ? implementers.first : nil
    }

    /// Lists the protocols and interfaces a set of supertypes amounts to, following refinements.
    ///
    /// - Parameters:
    ///   - direct: A type's resolved supertypes.
    ///   - hierarchy: The project's types.
    /// - Returns: Every protocol or interface reached, by `id`.
    private static func closure(_ direct: [DeclaredType], hierarchy: TypeHierarchy) -> Set<String> {
        var seen: Set<String> = [], queue = direct
        while let next = queue.popLast() {
            guard [.protocol, .interface].contains(next.fact.kind), seen.insert(next.id).inserted else { continue }
            queue += hierarchy.supertypes[next.id] ?? []
        }
        return seen
    }
}

/// The type names test code uses: names test files refer to or import, and supertypes their types declare.
struct TestSeams {
    private let names: Set<String>

    /// Gathers the names from every test file's facts.
    ///
    /// - Parameter index: The project's facts.
    init(index: ProjectIndex) {
        let tests = index.facts.values.filter { ProjectUnits.isTest($0.path) }
        let used = tests.flatMap { $0.module.references + $0.module.imports.flatMap(\.names) }
        let declared = tests.flatMap { $0.module.structure.types.flatMap(\.supertypes) }
        names = Set(used + declared)
    }

    /// Reports whether test code uses a name.
    ///
    /// - Parameter name: The type name.
    /// - Returns: Whether a test file mentions or implements it.
    func contains(_ name: String) -> Bool { names.contains(name) }
}
