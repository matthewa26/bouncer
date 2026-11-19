import Foundation
import BouncerCore

/// Flags two unrelated types that do the same things under different names: alternative classes with
/// different interfaces, which a shared protocol (and one set of names) would let callers swap. Off unless
/// configured.
///
/// Without knowing what methods mean, a method's shape stands in for its purpose: its parameter types in
/// order and its return type, for methods whose every parameter has a written type and that take at least
/// one. A shape counts only when it's unique within each type. Two types match when they share at least
/// `minMatches` shapes under different names, those are at least `minShare` of the smaller type's unique
/// shapes, and at least as many shared shapes differ in name as agree. Types related by inheritance or a
/// shared project supertype, types in the same file, test files, and shapes more than `maxSharers` types
/// share (visitor callbacks, `(String) -> String` helpers) are skipped.
public struct AlternativeInterfacesRule: ProjectRule {
    public let id = "alternative-interfaces"

    /// Creates the rule.
    public init() {}

    /// Flags each pair of types with matching method shapes under different names, once, at the first.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph and facts.
    ///   - targets: Unused; each finding lands at the first type of the pair.
    ///   - context: Repo-wide state; the rule only runs when configured, with `minMatches`, `minShare`, and
    ///     `maxSharers`.
    /// - Returns: One finding per pair.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        guard let settings = context.ruleSettings[id], settings.enabled else { return [] }
        let hierarchy = TypeHierarchy(index: index), shapes = MethodShapes(index: index, hierarchy: hierarchy)
        return ShapeMatcher(settings.parameters).pairs(in: shapes, hierarchy: hierarchy).map { pair in
            ProjectFinding.make(id, pair.lhs.path, pair.lhs.fact.line, Self.message(pair), context)
        }
    }

    /// Explains a pair.
    ///
    /// - Parameter pair: The two types and their matching methods.
    /// - Returns: The message.
    private static func message(_ pair: ShapeMatcher.Pair) -> String {
        let names = ManySubclassesRule.list(pair.matches.map { "\($0.0)()/\($0.1)()" })
        return "\"\(pair.lhs.name)\" and \"\(pair.rhs.name)\" (\(pair.rhs.path)) have \(pair.matches.count) methods "
            + "with the same signatures under different names (\(names)); if they do the same job, give them "
            + "one protocol and one set of names."
    }
}

/// Reads parameter and return types out of structure facts.
enum Signature {
    /// Reads a parameter's or field's bare type.
    ///
    /// - Parameter member: The member as `name:Type` or `name`.
    /// - Returns: Its bare type name, or `nil` if no type is written.
    static func type(_ member: String) -> String? {
        guard let colon = member.firstIndex(of: ":") else { return nil }
        let name = FactText.typeName(String(member[member.index(after: colon)...]))
        return name.isEmpty ? nil : name
    }

    /// Writes a method's shape: its written parameter types in order and its return type.
    ///
    /// - Parameter function: The method.
    /// - Returns: The shape, or `nil` for a method with no parameters or an untyped one.
    static func shape(of function: FunctionFact) -> String? {
        let types = function.parameters.map { member -> String? in
            member.firstIndex(of: ":").map { String(member[member.index(after: $0)...]) }
        }
        guard !types.isEmpty, types.allSatisfy({ $0 != nil }) else { return nil }
        return "(" + types.compactMap { $0 }.joined(separator: ",") + ")->" + (function.returns ?? "Void")
    }
}

/// Each project type's methods by shape, keeping only shapes unique within the type.
struct MethodShapes {
    /// Each type's `id`, then each unique shape's method name.
    let byType: [String: [String: String]]
    /// The types, by `id`.
    let types: [String: DeclaredType]

    /// Collects the shapes of every judged method.
    ///
    /// - Parameters:
    ///   - index: The project's facts.
    ///   - hierarchy: The project's types, for resolving each method's owner.
    init(index: ProjectIndex, hierarchy: TypeHierarchy) {
        let concrete = hierarchy.types.filter { !$0.fact.kind.isAbstract }
            .filter { !ProjectUnits.isIncidental($0.path, in: index) }
        let byKey = Dictionary(grouping: concrete) { ProjectUnits.family(of: $0.path) + ":" + $0.name }
        let methods = Self.methods(in: index).reduce(into: [String: [String: [String]]]()) { result, method in
            guard let type = byKey[method.key]?.first else { return }
            result[type.id, default: [:]][method.shape, default: []].append(method.name)
        }
        byType = methods.mapValues { $0.filter { Set($0.value).count == 1 }.mapValues { $0[0] } }
        types = Dictionary(concrete.map { ($0.id, $0) }) { first, _ in first }
    }

    /// Lists every judged method with a shape, keyed by its owner's language family and name.
    ///
    /// - Parameter index: The project's facts.
    /// - Returns: Each method's owner key, shape, and name.
    private static func methods(in index: ProjectIndex) -> [(key: String, shape: String, name: String)] {
        index.facts.filter { !ProjectUnits.isIncidental($0.key, in: index) }.flatMap { path, file in
            file.module.structure.functions.compactMap { function -> (key: String, shape: String, name: String)? in
                guard !function.name.hasSuffix(".init"), let owner = function.owner,
                      let shape = Signature.shape(of: function) else { return nil }
                return (ProjectUnits.family(of: path) + ":" + owner, shape, function.name)
            }
        }
    }
}

/// Pairs up types whose unique method shapes match under different names.
struct ShapeMatcher {
    /// Two types and their matching methods, as `(lhs name, rhs name)`.
    struct Pair {
        let lhs: DeclaredType
        let rhs: DeclaredType
        let matches: [(String, String)]
    }

    let minMatches: Int
    let minShare: Double
    let maxSharers: Int

    /// Reads the thresholds.
    ///
    /// - Parameter parameters: The rule's parameters: `minMatches` (3), `minShare` (0.5), `maxSharers` (4).
    init(_ parameters: RuleParameters) {
        minMatches = parameters.int("minMatches", default: 3)
        minShare = parameters.double("minShare", default: 0.5)
        maxSharers = parameters.int("maxSharers", default: 4)
    }

    /// Finds every matching pair.
    ///
    /// - Parameters:
    ///   - shapes: Each type's unique method shapes.
    ///   - hierarchy: The project's types, for which pairs are related.
    /// - Returns: The pairs, sorted by the first type's path and line.
    func pairs(in shapes: MethodShapes, hierarchy: TypeHierarchy) -> [Pair] {
        candidates(in: shapes).compactMap { first, second -> Pair? in
            guard let lhs = shapes.types[first], let rhs = shapes.types[second], lhs.path != rhs.path,
                  !Self.related(lhs, rhs, hierarchy: hierarchy) else { return nil }
            return pair(lhs, rhs, shapes: shapes)
        }.sorted { ($0.lhs.path, $0.lhs.fact.line, $0.rhs.path) < ($1.lhs.path, $1.lhs.fact.line, $1.rhs.path) }
    }

    /// Lists the pairs of types sharing at least `minMatches` shapes that few types share.
    ///
    /// - Parameter shapes: Each type's unique method shapes.
    /// - Returns: Each candidate pair of type `id`s, in order.
    private func candidates(in shapes: MethodShapes) -> [(String, String)] {
        let pairs = shapes.byType.flatMap { type, byShape in byShape.keys.map { (shape: $0, type: type) } }
        let owners = Dictionary(grouping: pairs, by: \.shape).values.map { $0.map(\.type).sorted() }
            .filter { $0.count > 1 && $0.count <= maxSharers }
        let counts = owners.flatMap { group in
            group.indices.flatMap { first in group[(first + 1)...].map { [group[first], $0] } }
        }.reduce(into: [[String]: Int]()) { $0[$1, default: 0] += 1 }
        return counts.filter { $0.value >= minMatches }.keys.map { ($0[0], $0[1]) }
    }

    /// Builds a pair if enough of its shared shapes differ in name.
    ///
    /// - Parameters:
    ///   - lhs: One type.
    ///   - rhs: The other.
    ///   - shapes: Each type's unique method shapes.
    /// - Returns: The pair, or `nil` if its methods mostly share names or cover too little of either type.
    private func pair(_ lhs: DeclaredType, _ rhs: DeclaredType, shapes: MethodShapes) -> Pair? {
        let left = shapes.byType[lhs.id] ?? [:], right = shapes.byType[rhs.id] ?? [:]
        let shared = left.keys.filter { right[$0] != nil }.sorted()
        let renamed = shared.compactMap { shape -> (String, String)? in
            guard let first = left[shape], let second = right[shape] else { return nil }
            return first == second ? nil : (first, second)
        }
        guard renamed.count >= minMatches, renamed.count * 2 >= shared.count,
              Double(renamed.count) >= minShare * Double(min(left.count, right.count)) else { return nil }
        return Pair(lhs: lhs, rhs: rhs, matches: renamed)
    }

    /// Reports whether two types are related: one inherits from the other, or they share a project supertype.
    ///
    /// - Parameters:
    ///   - lhs: One type.
    ///   - rhs: The other.
    ///   - hierarchy: The project's types.
    /// - Returns: Whether they're in one hierarchy.
    private static func related(_ lhs: DeclaredType, _ rhs: DeclaredType, hierarchy: TypeHierarchy) -> Bool {
        let up = { (type: DeclaredType) -> Set<String> in
            let abstractions = Conformances.abstractions(of: type, hierarchy: hierarchy)
            return Set([type.id] + (hierarchy.ancestors(of: type) + abstractions).map(\.id)
                + (hierarchy.supertypes[type.id] ?? []).map(\.id))
        }
        return !up(lhs).isDisjoint(with: up(rhs))
    }
}
