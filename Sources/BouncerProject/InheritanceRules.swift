import Foundation
import BouncerCore

/// Flags a class whose depth of inheritance (DIT) within the project is over the limit.
///
/// Depth counts parent classes declared in the project, so a class extending `NSObject` or
/// `React.Component` directly has depth 0; with multiple inheritance (Python) it's the longest chain.
public struct DeepInheritanceRule: ProjectRule {
    public let id = "deep-inheritance"

    /// Creates the rule.
    public init() {}

    /// Flags each class more than `maxDepth` project classes deep.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph and facts.
    ///   - targets: Unused; each finding lands at the class.
    ///   - context: Repo-wide state, including the `maxDepth` parameter.
    /// - Returns: One finding per over-deep class.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let limit = context.settings(for: id).parameters.int("maxDepth", default: 4)
        let hierarchy = TypeHierarchy(index: index)
        let classes = hierarchy.types.filter { $0.fact.kind.isClass && !ProjectUnits.isIncidental($0.path, in: index) }
        return classes.compactMap { type in
            let depth = hierarchy.depth(of: type)
            guard depth > limit else { return nil }
            let message = Self.message(type, depth: depth, limit: limit, hierarchy: hierarchy)
            return ProjectFinding.make(id, type.path, type.fact.line, message, context)
        }
    }

    /// Explains an over-deep class, naming its chain of ancestors.
    ///
    /// - Parameters:
    ///   - type: The class.
    ///   - depth: Its depth.
    ///   - limit: The allowed depth.
    ///   - hierarchy: The project's types.
    /// - Returns: The message.
    private static func message(_ type: DeclaredType, depth: Int, limit: Int, hierarchy: TypeHierarchy) -> String {
        let chain = ([type] + hierarchy.ancestors(of: type).prefix(depth)).map(\.name).joined(separator: " → ")
        return "Class \"\(type.name)\" is \(depth) levels deep in the project's inheritance tree (\(chain)), "
            + "over the \(limit) limit; prefer composition over more subclassing."
    }
}

/// Flags a class with more direct subclasses in the project (NOC) than allowed. Off unless configured.
///
/// Classes and subclasses in test, DocC, and generated files don't count.
public struct ManySubclassesRule: ProjectRule {
    public let id = "many-subclasses"

    /// Creates the rule.
    public init() {}

    /// Flags each class with more than `maxChildren` direct subclasses.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph and facts.
    ///   - targets: Unused; each finding lands at the class.
    ///   - context: Repo-wide state; the rule only runs when configured, with `maxChildren`.
    /// - Returns: One finding per class with too many children.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        guard let settings = context.ruleSettings[id], settings.enabled else { return [] }
        let limit = settings.parameters.int("maxChildren", default: 10)
        let hierarchy = TypeHierarchy(index: index)
        let judged = { (type: DeclaredType) in !ProjectUnits.isIncidental(type.path, in: index) }
        return hierarchy.types.filter(judged).compactMap { type in
            let children = Set((hierarchy.children[type.id] ?? []).filter(judged).map(\.name)).sorted()
            guard children.count > limit else { return nil }
            return ProjectFinding.make(id, type.path, type.fact.line, Self.message(type, children, limit), context)
        }
    }

    /// Explains a class with too many subclasses.
    ///
    /// - Parameters:
    ///   - type: The class.
    ///   - children: Its subclasses' names, sorted.
    ///   - limit: The allowed number.
    /// - Returns: The message.
    private static func message(_ type: DeclaredType, _ children: [String], _ limit: Int) -> String {
        "Class \"\(type.name)\" has \(children.count) direct subclasses, over the \(limit) limit "
            + "(\(list(children))); a change to it ripples into all of them."
    }

    /// Lists names, eliding all but the first five.
    ///
    /// - Parameter names: The names.
    /// - Returns: A comma-separated list.
    static func list(_ names: [String]) -> String {
        names.prefix(shownNames).joined(separator: ", ") + (names.count > shownNames ? ", …" : "")
    }

    /// How many names a message lists before eliding the rest.
    static let shownNames = 5
}

/// Flags a subclass that overrides inherited methods only to throw, trap, or do nothing: it refuses
/// part of what it inherits, so it can't stand in for its parent.
///
/// A method counts when a project ancestor declares it with a real body and the subclass's version only
/// throws (`throw`, `fatalError`, `raise NotImplementedError`) or is empty. A Swift `override` of a class
/// outside the project counts only if it throws or traps. Test files are skipped, since mocks do this.
public struct RefusedBequestRule: ProjectRule {
    public let id = "refused-bequest"

    /// Creates the rule.
    public init() {}

    /// Flags each subclass with refused methods.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph and facts.
    ///   - targets: Unused; each finding lands at the subclass.
    ///   - context: Repo-wide state.
    /// - Returns: One finding per refusing subclass.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let hierarchy = TypeHierarchy(index: index)
        let judged = hierarchy.types.filter { $0.fact.kind.isClass && !ProjectUnits.isIncidental($0.path, in: index) }
        return judged.compactMap { type in
            let refused = refusedMethods(of: type, hierarchy: hierarchy)
            guard !refused.isEmpty else { return nil }
            return ProjectFinding.make(id, type.path, type.fact.line, Self.message(type, refused), context)
        }
    }

    /// Explains a refusing subclass.
    ///
    /// - Parameters:
    ///   - type: The subclass.
    ///   - refused: Its refused methods' names.
    /// - Returns: The message.
    private static func message(_ type: DeclaredType, _ refused: [String]) -> String {
        let names = refused.map { "\($0)()" }.joined(separator: ", ")
        return "\"\(type.name)\" overrides \(names) only to throw or do nothing; it refuses what it inherits, "
            + "so it can't stand in for its parent. Use composition or split the parent."
    }

    /// Lists a class's methods that refuse an inherited implementation.
    ///
    /// - Parameters:
    ///   - type: The class.
    ///   - hierarchy: The project's types.
    /// - Returns: The refused methods' names, in declaration order.
    private func refusedMethods(of type: DeclaredType, hierarchy: TypeHierarchy) -> [String] {
        let ancestors = hierarchy.ancestors(of: type), fact = type.fact
        return fact.methods.filter { fact.refused.contains($0) || fact.empty.contains($0) }.filter { name in
            guard let declaring = ancestors.first(where: { $0.fact.methods.contains(name) }) else {
                return type.path.hasSuffix(".swift") && fact.refused.contains(name) && !fact.supertypes.isEmpty
            }
            return !declaring.fact.refused.contains(name) && !declaring.fact.empty.contains(name)
        }
    }
}

/// Flags two type hierarchies that mirror each other: for each subtype of one there's a like-named
/// subtype of the other, such as `CircleShape`/`CircleRenderer` and `SquareShape`/`SquareRenderer`, so
/// adding a case means adding a class to both.
///
/// Each class, protocol, or interface with direct subtypes is a hierarchy; a subtype's stem is its name
/// without the parent's name (or the subtypes' common suffix or prefix). Two hierarchies are parallel when
/// at least `minPairs` stems match and they cover at least `minShare` of the smaller hierarchy.
public struct ParallelInheritanceRule: ProjectRule {
    public let id = "parallel-inheritance"

    /// Creates the rule.
    public init() {}

    /// Flags each pair of parallel hierarchies once, at the first one's root.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph and facts.
    ///   - targets: Unused; each finding lands at a hierarchy's root.
    ///   - context: Repo-wide state, with `minPairs` and `minShare`.
    /// - Returns: One finding per pair.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let parameters = context.settings(for: id).parameters
        let minPairs = parameters.int("minPairs", default: 3), minShare = parameters.double("minShare", default: 0.75)
        let families = HierarchyStems.families(in: index, minSize: minPairs)
        return families.indices.flatMap { first in
            families[(first + 1)...].compactMap { second in
                finding(families[first], second, minPairs: minPairs, minShare: minShare, context: context)
            }
        }
    }

    /// Compares two hierarchies and reports them if they're parallel.
    ///
    /// - Parameters:
    ///   - lhs: One hierarchy.
    ///   - rhs: Another.
    ///   - minPairs: The fewest matching stems.
    ///   - minShare: The smallest share of the smaller hierarchy's stems that must match.
    ///   - context: Repo-wide state.
    /// - Returns: The finding, or `nil` if they aren't parallel.
    private func finding(
        _ lhs: HierarchyStems, _ rhs: HierarchyStems, minPairs: Int, minShare: Double, context: AnalysisContext
    ) -> Finding? {
        let shared = lhs.matches(rhs)
        let smaller = min(lhs.stems.count, rhs.stems.count)
        guard shared.count >= minPairs, Double(shared.count) >= minShare * Double(smaller) else { return nil }
        let message = "\"\(lhs.root.name)\" and \"\(rhs.root.name)\" (\(rhs.root.path)) are parallel "
            + "hierarchies: \(shared.count) of their subtypes pair up by name (\(ManySubclassesRule.list(shared))), "
            + "so each new case needs a class in both; merge them or move the varying part into one."
        return ProjectFinding.make(id, lhs.root.path, lhs.root.fact.line, message, context)
    }
}

/// One hierarchy's root and its direct subtypes, keyed by the stem that distinguishes each.
struct HierarchyStems {
    let root: DeclaredType
    /// Each stem's subtype name.
    let stems: [String: String]

    /// Lists every hierarchy with at least `minSize` named subtypes, sorted by path and line, leaving out
    /// test, DocC, and generated types as roots and as subtypes.
    ///
    /// - Parameters:
    ///   - index: The project's facts.
    ///   - minSize: The fewest subtypes a hierarchy needs to be compared.
    /// - Returns: The hierarchies.
    static func families(in index: ProjectIndex, minSize: Int) -> [HierarchyStems] {
        let hierarchy = TypeHierarchy(index: index)
        let types = hierarchy.types.filter { !ProjectUnits.isIncidental($0.path, in: index) }
        let pairs = types.flatMap { kid in (hierarchy.supertypes[kid.id] ?? []).map { (parent: $0.id, child: kid) } }
        let subtypes = Dictionary(grouping: pairs, by: \.parent)
        return types.compactMap { root in
            let children = Set((subtypes[root.id] ?? []).map(\.child.name)).sorted()
            guard children.count >= minSize else { return nil }
            return HierarchyStems(root: root, stems: stems(of: children, root: root.name))
        }
    }

    /// Lists the stems two hierarchies share, where the subtypes behind each stem differ by name.
    ///
    /// - Parameter other: The other hierarchy.
    /// - Returns: The shared stems, sorted.
    func matches(_ other: HierarchyStems) -> [String] {
        stems.keys.filter { stem in other.stems[stem].map { $0 != stems[stem] } ?? false }.sorted()
    }

    /// Strips each subtype's name down to its stem: without the root's name as a suffix or prefix, else
    /// without the subtypes' longest common suffix or prefix.
    ///
    /// - Parameters:
    ///   - names: The subtypes' names.
    ///   - root: The root's name.
    /// - Returns: Each non-empty stem's subtype name.
    private static func stems(of names: [String], root: String) -> [String: String] {
        let suffix = names.allSatisfy { $0.hasSuffix(root) } ? root : WordAffix.commonSuffix(names)
        let prefix = names.allSatisfy { $0.hasPrefix(root) } ? root : WordAffix.commonPrefix(names)
        let pairs = names.map { name -> (String, String) in
            if !suffix.isEmpty { return (String(name.dropLast(suffix.count)), name) }
            return (String(name.dropFirst(prefix.count)), name)
        }
        return Dictionary(pairs.filter { !$0.0.isEmpty }) { first, _ in first }
    }
}

/// Finds the camel-case words a set of names shares at either end.
enum WordAffix {
    /// The longest run of whole words every name ends with.
    ///
    /// - Parameter names: The names.
    /// - Returns: The shared suffix, or `""`.
    static func commonSuffix(_ names: [String]) -> String {
        let words = names.map(Self.words)
        guard let shortest = words.map(\.count).min() else { return "" }
        let count = (0...shortest).last { length in Set(words.map { $0.suffix(length) }).count == 1 } ?? 0
        return count == 0 ? "" : words[0].suffix(count).joined()
    }

    /// The longest run of whole words every name starts with.
    ///
    /// - Parameter names: The names.
    /// - Returns: The shared prefix, or `""`.
    static func commonPrefix(_ names: [String]) -> String {
        let words = names.map(Self.words)
        guard let shortest = words.map(\.count).min() else { return "" }
        let count = (0...shortest).last { length in Set(words.map { $0.prefix(length) }).count == 1 } ?? 0
        return count == 0 ? "" : words[0].prefix(count).joined()
    }

    /// Splits a camel-case or snake-case name into words, keeping each word's original text.
    ///
    /// - Parameter name: The name.
    /// - Returns: Its words; joined, they rebuild the name.
    static func words(_ name: String) -> [String] {
        var words: [String] = []
        for character in name {
            if words.isEmpty || character.isUppercase || character == "_" { words.append("") }
            words[words.count - 1].append(character)
        }
        return words
    }
}
