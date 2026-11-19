import Foundation
import BouncerCore

/// Flags two types in different files that each read the other's fields: inappropriate intimacy, where
/// two classes know each other's internals and change together.
///
/// Without type information, a read counts only when the value's type is known: a parameter, property, or
/// local whose type is written (or constructed with `Foo(…)`/`new Foo()`), read as `value.member` or
/// `self.value.member`. A member counts as internal when it's one of the other type's stored fields (not a
/// Swift `public` one) or, in TS/JS and Python, when its name starts with `_` (but not `__`). A pair is
/// reported when each side reads at least `minFields` of the other's. Test, DocC, and generated files are
/// skipped.
public struct InappropriateIntimacyRule: ProjectRule {
    public let id = "inappropriate-intimacy"

    /// Creates the rule.
    public init() {}

    /// Flags each pair of types reading each other's internals, once, at the first by path.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph and facts.
    ///   - targets: Unused; each finding lands at the first type of the pair.
    ///   - context: Repo-wide state, with `minFields`.
    /// - Returns: One finding per intimate pair.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let minFields = context.settings(for: id).parameters.int("minFields", default: 2)
        let collaborations = Collaborations(index: index), reads = collaborations.internalReads()
        let types = Dictionary(collaborations.hierarchy.types.map { ($0.id, $0) }) { first, _ in first }
        return reads.flatMap { readerID, owners in
            owners.compactMap { ownerID, there in
                let back = reads[ownerID]?[readerID] ?? []
                return finding(types[readerID], types[ownerID], there, back, minFields: minFields, context: context)
            }
        }.sorted { ($0.filePath.path, $0.line, $0.message) < ($1.filePath.path, $1.line, $1.message) }
    }

    /// Builds a pair's finding if both read enough of each other, reporting it from the first by path.
    ///
    /// - Parameters:
    ///   - reader: One type.
    ///   - owner: The type it reads.
    ///   - there: The fields of `owner` that `reader` reads.
    ///   - back: The fields of `reader` that `owner` reads.
    ///   - minFields: The fewest fields each must read.
    ///   - context: Repo-wide state.
    /// - Returns: The finding, or `nil`.
    private func finding(
        _ reader: DeclaredType?, _ owner: DeclaredType?, _ there: Set<String>, _ back: Set<String>,
        minFields: Int, context: AnalysisContext
    ) -> Finding? {
        guard let reader, let owner, reader.path < owner.path, min(there.count, back.count) >= minFields else {
            return nil
        }
        return ProjectFinding.make(id, reader.path, reader.fact.line, Self.message(reader, owner, there, back), context)
    }

    /// Explains an intimate pair.
    ///
    /// - Parameters:
    ///   - lhs: The type reported.
    ///   - rhs: The other type.
    ///   - there: The fields of `rhs` that `lhs` reads.
    ///   - back: The fields of `lhs` that `rhs` reads.
    /// - Returns: The message.
    private static func message(_ lhs: DeclaredType, _ rhs: DeclaredType, _ there: Set<String>, _ back: Set<String>)
        -> String {
        let forward = ManySubclassesRule.list(there.sorted().map { "\(rhs.name).\($0)" })
        let backward = ManySubclassesRule.list(back.sorted().map { "\(lhs.name).\($0)" })
        return "\"\(lhs.name)\" and \"\(rhs.name)\" (\(rhs.path)) read each other's fields (\(forward); "
            + "\(backward)); move the behavior next to the data it uses, or merge the two."
    }
}

/// Flags a type that constructs its collaborators itself where an abstraction exists or the collaborator
/// is a service: dependency inversion asks for them to be passed in. Off unless configured.
///
/// Only constructions kept in a property count: a stored property's initial value, `self.x = Foo()`, or
/// `this.x = new Foo()`; a temporary built inside a method is a value, not a collaborator. A kept project type
/// counts when it's a class implementing a project protocol, interface, or abstract class, or when its name
/// ends in `Service`, `Repository`, `Client`, `Gateway`, `Store`, `Manager`, or `API`. It doesn't count when an
/// initializer of the constructing type already takes it or its abstraction (a default argument such as
/// `init(api: API = LiveAPI())` is injection), when it's an error type, or when the constructing type is a
/// composition root: its name or a supertype's ends in `Factory`, `Builder`, `Container`, `Assembly`, `App`,
/// `Registry`, `Command`, or similar. Test, DocC, and generated files are skipped.
public struct DependencyInversionRule: ProjectRule {
    public let id = "dependency-inversion"
    private static let serviceSuffixes = ["Service", "Repository", "Client", "Gateway", "Store", "Manager", "API"]
    private static let rootSuffixes = [
        "Factory", "Builder", "Container", "Assembly", "Assembler", "Module", "App", "Application", "Main",
        "Bootstrap", "Injector", "Provider", "Registry", "Configuration", "Config", "Coordinator", "Composer",
        "Command"
    ]

    /// Creates the rule.
    public init() {}

    /// Flags each type that constructs collaborators it should receive.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph and facts.
    ///   - targets: Unused; each finding lands at the constructing type or extension.
    ///   - context: Repo-wide state; the rule only runs when configured.
    /// - Returns: One finding per constructing type or extension.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        guard context.ruleSettings[id]?.enabled == true else { return [] }
        let collaborations = Collaborations(index: index), injected = Self.initializerTypes(in: index)
        return collaborations.entries.compactMap { entry -> Finding? in
            guard !entry.owner.fact.kind.isAbstract, !Self.isRoot(entry.owner) else { return nil }
            let taken = injected[entry.owner.name] ?? [], owner = entry.owner
            let offenders = entry.fact.constructs.compactMap { offender($0, owner, taken, collaborations) }
            let message = Self.message(owner.name, offenders)
            return offenders.isEmpty ? nil : ProjectFinding.make(id, entry.path, entry.fact.line, message, context)
        }
    }

    /// Explains a type constructing its collaborators.
    ///
    /// - Parameters:
    ///   - owner: The constructing type's name.
    ///   - offenders: The constructed types, described.
    /// - Returns: The message.
    private static func message(_ owner: String, _ offenders: [String]) -> String {
        let them = offenders.count == 1 ? "it (or its abstraction)" : "them (or their abstractions)"
        return "\"\(owner)\" constructs and keeps \(ManySubclassesRule.list(offenders)) itself; take \(them) "
            + "through the initializer so callers can substitute a different implementation."
    }

    /// Describes a constructed type if constructing it inverts a dependency.
    ///
    /// - Parameters:
    ///   - name: The constructed type's written name.
    ///   - owner: The constructing type.
    ///   - taken: The bare types the owner's initializers take.
    ///   - collaborations: The project's types.
    /// - Returns: `Name` or `Name (a Protocol)`, or `nil` if it doesn't count.
    private func offender(
        _ name: String, _ owner: DeclaredType, _ taken: Set<String>, _ collaborations: Collaborations
    ) -> String? {
        guard let type = collaborations.hierarchy.resolver.resolve(name, from: owner), type.id != owner.id,
              !type.fact.kind.isAbstract, type.fact.kind != .enum, !Self.isError(type.name),
              !taken.contains(type.name) else { return nil }
        let abstractions = Conformances.abstractions(of: type, hierarchy: collaborations.hierarchy)
        guard !abstractions.contains(where: { taken.contains($0.name) }) else { return nil }
        if type.fact.kind.isClass, let abstraction = abstractions.first(where: { !Self.isLanguageProtocol($0) }) {
            return "\(name) (implementing \(abstraction.name))"
        }
        return Self.serviceSuffixes.contains(where: name.hasSuffix) ? name : nil
    }

    /// Reports whether an abstraction is a marker or a language protocol, such as a mapping, sequence, or
    /// context manager, rather than a service seam: none of its requirements (or, without stubbed requirements,
    /// its methods) is a named method other than a `__dunder__` method or an operator.
    ///
    /// - Parameter abstraction: The protocol, interface, or abstract class.
    /// - Returns: Whether it offers callers no service to substitute.
    private static func isLanguageProtocol(_ abstraction: DeclaredType) -> Bool {
        let required = Conformances.requirements(of: abstraction)
        let names = required.isEmpty ? abstraction.fact.methods : required
        return names.allSatisfy { name in
            (name.hasPrefix("__") && name.hasSuffix("__")) || name.first.map { !$0.isLetter && $0 != "_" } == true
        }
    }

    /// Lists the bare types each type's initializers take, by type name.
    ///
    /// - Parameter index: The project's facts.
    /// - Returns: Each type's initializer parameter types.
    private static func initializerTypes(in index: ProjectIndex) -> [String: Set<String>] {
        let initializers = index.facts.values.flatMap(\.module.structure.functions)
            .filter { $0.name.hasSuffix(".init") }
        let pairs = initializers.map { function in
            (String(function.name.dropLast(".init".count)), Set(function.parameters.compactMap(Signature.type)))
        }
        return Dictionary(pairs, uniquingKeysWith: { $0.union($1) })
    }

    /// Reports whether a type is a composition root, where constructing collaborators belongs: its name or a
    /// supertype's (such as `ParsableCommand` or `App`) ends in a composition-root suffix.
    ///
    /// - Parameter type: The type.
    /// - Returns: Whether it's a composition root.
    private static func isRoot(_ type: DeclaredType) -> Bool {
        ([type.name] + type.fact.supertypes).contains { name in rootSuffixes.contains(where: name.hasSuffix) }
    }

    /// Reports whether a type is an error by name.
    ///
    /// - Parameter name: The type's name.
    /// - Returns: Whether it ends in `Error` or `Exception`.
    private static func isError(_ name: String) -> Bool { name.hasSuffix("Error") || name.hasSuffix("Exception") }
}

/// Each type's collaboration facts, resolved to the project's types.
struct Collaborations {
    /// One collaboration fact with the type it belongs to.
    struct Entry {
        let owner: DeclaredType
        let path: String
        let fact: CollaborationFact
    }

    let hierarchy: TypeHierarchy
    /// Every judged fact whose owner resolves to a project type, sorted by path and line.
    let entries: [Entry]
    private let index: ProjectIndex

    /// Resolves every non-test file's collaboration facts.
    ///
    /// - Parameter index: The project's facts.
    init(index: ProjectIndex) {
        let hierarchy = TypeHierarchy(index: index)
        (self.hierarchy, self.index) = (hierarchy, index)
        entries = index.facts.keys.sorted().filter { !ProjectUnits.isIncidental($0, in: index) }.flatMap { path in
            (index.facts[path]?.module.structure.collaborations ?? []).compactMap { fact in
                Self.owner(of: fact, path: path, hierarchy: hierarchy, index: index).map {
                    Entry(owner: $0, path: path, fact: fact)
                }
            }
        }
    }

    /// Resolves a fact's owner, preferring a type of that name declared in the same file.
    ///
    /// - Parameters:
    ///   - fact: The collaboration fact.
    ///   - path: Its file.
    ///   - hierarchy: The project's types.
    ///   - index: The project's facts, for the file's module.
    /// - Returns: The owning type, or `nil` if it isn't declared in the project.
    private static func owner(
        of fact: CollaborationFact, path: String, hierarchy: TypeHierarchy, index: ProjectIndex
    ) -> DeclaredType? {
        if let local = hierarchy.types.first(where: { $0.path == path && $0.name == fact.owner }) { return local }
        let probe = TypeFact(name: fact.owner, line: fact.line, kind: .extension)
        let site = DeclaredType(fact: probe, path: path, unit: ProjectUnits.unit(of: path, in: index))
        return hierarchy.resolver.resolve(fact.owner, from: site)
    }

    /// Lists, for each type, the internals of other types it reads.
    ///
    /// - Returns: Each reader's reads by `id`, keyed by the read type's `id`, as member names.
    func internalReads() -> [String: [String: Set<String>]] {
        var reads: [String: [String: Set<String>]] = [:]
        for entry in entries {
            for (read, member) in entry.fact.uses.compactMap({ internalRead($0, by: entry.owner) }) {
                reads[entry.owner.id, default: [:]][read.id, default: []].insert(member)
            }
        }
        return reads
    }

    /// Resolves one use to the project type it reads, if the member is one of that type's internals.
    ///
    /// - Parameters:
    ///   - use: The use, as `Type.member`.
    ///   - reader: The type reading it.
    /// - Returns: The read type and member, or `nil`.
    private func internalRead(_ use: String, by reader: DeclaredType) -> (DeclaredType, String)? {
        let parts = use.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, let read = hierarchy.resolver.resolve(parts[0], from: reader), read.id != reader.id,
              !ProjectUnits.isIncidental(read.path, in: index), isInternal(parts[1], of: read) else { return nil }
        return (read, parts[1])
    }

    /// Reports whether a member is one of a type's internals: a stored field that isn't Swift `public`, or a
    /// TS/JS or Python name with a single leading underscore.
    ///
    /// - Parameters:
    ///   - member: The member's name.
    ///   - type: The type.
    /// - Returns: Whether reading it from outside is intimate.
    private func isInternal(_ member: String, of type: DeclaredType) -> Bool {
        if !type.path.hasSuffix(".swift"), member.hasPrefix("_"), !member.hasPrefix("__") { return true }
        guard type.fact.fields.contains(where: { $0.prefix { $0 != ":" } == member }) else { return false }
        let exports = index.facts[type.path]?.module.exports ?? []
        return !exports.contains { $0.name == member }
    }
}
