import Foundation
import BouncerCore

/// Flags a data clump: the same three or more parameters or fields, by name and type where written,
/// appearing together in several functions and types across files, which suggests a missing type.
///
/// A function's parameters and a type's stored fields count alike; an initializer counts with its type,
/// and functions sharing a name (overloads, overrides, protocol requirements and their implementations)
/// count once. Functions and types with more than `maxMembers` members, and test, DocC, and generated files,
/// are skipped. A clump a type already holds as fields is reported only if `minOccurrences` functions still
/// pass it loose, and numbered names such as `spec1, spec2, spec3` (an overload set) aren't a clump.
public struct DataClumpRule: ProjectRule {
    public let id = "data-clump"

    /// Creates the rule.
    public init() {}

    /// Flags each clump of at least `minMembers` members shared by at least `minOccurrences` functions or
    /// types in two or more files, once, at its first occurrence.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph and facts.
    ///   - targets: Unused; each finding lands at the clump's first occurrence.
    ///   - context: Repo-wide state, with `minMembers`, `minOccurrences`, and `maxMembers`.
    /// - Returns: One finding per clump.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let parameters = context.settings(for: id).parameters
        let finder = ClumpFinder(
            minMembers: parameters.int("minMembers", default: 3), maxMembers: parameters.int("maxMembers", default: 12),
            minOccurrences: parameters.int("minOccurrences", default: 4)
        )
        return finder.clumps(in: MemberOwner.all(in: index)).map { clump in
            ProjectFinding.make(id, clump.owners[0].path, clump.owners[0].line, Self.message(clump), context)
        }
    }

    /// Explains a clump.
    ///
    /// - Parameter clump: The clump.
    /// - Returns: The message.
    private static func message(_ clump: Clump) -> String {
        let members = clump.members.map { $0.replacingOccurrences(of: ":", with: ": ") }.joined(separator: ", ")
        let files = Set(clump.owners.map(\.path)).count
        let names = ManySubclassesRule.list(clump.owners.map(\.display))
        return "\(members) appear together in \(clump.owners.count) functions and types across \(files) files "
            + "(\(names)); group them into one type."
    }
}

/// A function or type and the parameters or fields it declares.
struct MemberOwner: Sendable {
    /// Identifies the owner across files: `func:<name>`, or `type:<name>` for a type and its initializers.
    let key: String
    let display: String
    let path: String
    let line: Int
    let members: [String]
    /// Whether it's a type's fields rather than a function's parameters.
    let isType: Bool

    /// Lists every non-test function's parameters and type's fields.
    ///
    /// - Parameter index: The project's facts.
    /// - Returns: The owners, sorted by path and line.
    static func all(in index: ProjectIndex) -> [MemberOwner] {
        index.facts.keys.sorted().filter { !ProjectUnits.isIncidental($0, in: index) }.flatMap { path in
            let structure = index.facts[path]?.module.structure ?? StructureFacts()
            let family = ProjectUnits.family(of: path)
            let types = structure.types.map { type in
                MemberOwner(key: "\(family):type:\(type.name)", display: type.name, path: path, line: type.line,
                            members: type.fields, isType: true)
            }
            return types + structure.functions.map { owner(of: $0, family: family, path: path) }
        }
    }

    /// Describes one function as an owner, keying an initializer to its type.
    ///
    /// - Parameters:
    ///   - function: The function.
    ///   - family: Its language family.
    ///   - path: Its file.
    /// - Returns: The owner.
    private static func owner(of function: FunctionFact, family: String, path: String) -> MemberOwner {
        let isInit = function.name.hasSuffix(".init")
        let key = isInit ? "\(family):type:\(function.name.dropLast(".init".count))" : "\(family):func:\(function.name)"
        return MemberOwner(key: key, display: function.name + "()", path: path, line: function.line,
                           members: function.parameters, isType: false)
    }
}

/// A set of members and the owners that declare all of them.
struct Clump {
    let members: [String]
    /// One occurrence per distinct owner key, sorted by path and line.
    let owners: [MemberOwner]
}

/// Finds data clumps by counting every `minMembers`-sized combination of each owner's members.
struct ClumpFinder {
    let minMembers: Int
    let maxMembers: Int
    let minOccurrences: Int

    /// Finds the clumps, largest first, leaving out any whose members are a subset of a reported one.
    ///
    /// - Parameter owners: Every owner.
    /// - Returns: The clumps.
    func clumps(in owners: [MemberOwner]) -> [Clump] {
        var occurrences: [[String]: [String: MemberOwner]] = [:]
        for owner in owners where (minMembers...maxMembers).contains(Set(owner.members).count) {
            for combination in Self.combinations(Set(owner.members).sorted(), size: minMembers) {
                occurrences[combination, default: [:]][owner.key] = occurrences[combination]?[owner.key] ?? owner
            }
        }
        return merged(occurrences.filter { !Self.isNumbered($0.key) && isClump(Array($0.value.values)) })
    }

    /// Reports whether a combination's owners make it a clump: enough of them, in more than one file, and
    /// not already a type's fields with only a few functions still passing them loose.
    ///
    /// - Parameter owners: One occurrence per owner key.
    /// - Returns: Whether it's a clump.
    private func isClump(_ owners: [MemberOwner]) -> Bool {
        let loose = owners.filter { !$0.isType }.count
        return owners.count >= minOccurrences && Set(owners.map(\.path)).count > 1
            && (loose >= minOccurrences || !owners.contains(where: \.isType))
    }

    /// Reports whether members are one name numbered, such as `spec1`, `spec2`, `spec3`: an overload set
    /// taking one, two, or three of a thing, not a missing type.
    ///
    /// - Parameter members: The members, as `name:Type` or `name`.
    /// - Returns: Whether every name is the same after dropping trailing digits.
    private static func isNumbered(_ members: [String]) -> Bool {
        let stems = Set(members.map { $0.prefix { $0 != ":" } }.map { $0.prefix { !$0.isNumber } })
        return stems.count == 1 && members.allSatisfy { $0.prefix { $0 != ":" }.last?.isNumber == true }
    }

    /// Merges combinations shared by exactly the same owners into one clump each, then drops clumps whose
    /// members another reported clump already contains.
    ///
    /// - Parameter frequent: Each frequent combination's owners by key.
    /// - Returns: The clumps, largest first, then by first occurrence.
    private func merged(_ frequent: [[String]: [String: MemberOwner]]) -> [Clump] {
        let candidates = Dictionary(grouping: frequent) { Set($0.value.keys) }.values.map { group in
            let owners = group[0].value.values.sorted { ($0.path, $0.line) < ($1.path, $1.line) }
            return Clump(members: Set(group.flatMap(\.key)).sorted(), owners: owners)
        }.sorted(by: Self.isLarger)
        return candidates.reduce(into: []) { reported, clump in
            if !reported.contains(where: { Set($0.members).isSuperset(of: clump.members) }) { reported.append(clump) }
        }
    }

    /// Orders clumps by size, largest first, then by their first occurrence.
    ///
    /// - Parameters:
    ///   - lhs: One clump.
    ///   - rhs: Another.
    /// - Returns: Whether `lhs` comes first.
    private static func isLarger(_ lhs: Clump, _ rhs: Clump) -> Bool {
        if lhs.members.count != rhs.members.count { return lhs.members.count > rhs.members.count }
        let left = (lhs.owners[0].path, lhs.owners[0].line, lhs.members.joined(separator: ","))
        return left < (rhs.owners[0].path, rhs.owners[0].line, rhs.members.joined(separator: ","))
    }

    /// Lists every combination of a given size, in order.
    ///
    /// - Parameters:
    ///   - items: The sorted items.
    ///   - size: The combination size.
    /// - Returns: The combinations.
    static func combinations(_ items: [String], size: Int) -> [[String]] {
        guard size > 0 else { return [[]] }
        guard items.count >= size else { return [] }
        return items.indices.flatMap { start in
            combinations(Array(items[(start + 1)...]), size: size - 1).map { [items[start]] + $0 }
        }
    }
}

/// Flags the same `switch` subject, such as `switch shape.kind`, repeated across files with the same cases:
/// each new case has to be added to every one of them, which polymorphism or a single lookup table avoids.
///
/// Subjects are compared after removing whitespace, wrapping parentheses, and a leading `self.`/`this.`;
/// `switch self`, literals, and tuples are skipped. A `switch` counts only if it shares at least
/// `minSharedCases` case labels with one in another file, so walkers that switch on a parser's node type for
/// different cases don't. Test files and subjects in `ignoreSubjects` are skipped.
public struct RepeatedSwitchRule: ProjectRule {
    public let id = "repeated-switch"

    /// Creates the rule.
    public init() {}

    /// Flags each subject switched on with shared cases at least `minOccurrences` times in at least
    /// `minFiles` files, once, at its first occurrence.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph and facts.
    ///   - targets: Unused; each finding lands at the subject's first `switch`.
    ///   - context: Repo-wide state, with `minOccurrences`, `minFiles`, `minSharedCases`, and `ignoreSubjects`.
    /// - Returns: One finding per repeated subject.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let parameters = context.settings(for: id).parameters
        let minOccurrences = parameters.int("minOccurrences", default: 3)
        let minFiles = parameters.int("minFiles", default: 3), minShared = parameters.int("minSharedCases", default: 2)
        let ignored = Set(parameters.stringList("ignoreSubjects", default: []))
        let groups = Dictionary(grouping: SwitchUse.all(in: index).filter { !ignored.contains($0.subject) }, by: \.key)
        return groups.values.map { SwitchUse.related($0, minShared: minShared) }
            .filter { $0.count >= minOccurrences && Set($0.map(\.path)).count >= minFiles }
            .sorted { ($0[0].path, $0[0].line) < ($1[0].path, $1[0].line) }
            .map { ProjectFinding.make(id, $0[0].path, $0[0].line, Self.message($0), context) }
    }

    /// Explains a repeated subject.
    ///
    /// - Parameter uses: Its related `switch` statements, in order.
    /// - Returns: The message.
    private static func message(_ uses: [SwitchUse]) -> String {
        let places = ManySubclassesRule.list(uses.map { "\($0.path):\($0.line)" })
        return "`switch \(uses[0].subject)` with the same cases appears \(uses.count) times across "
            + "\(Set(uses.map(\.path)).count) files (\(places)); each new case must be added everywhere. Move the "
            + "varying behavior into the type (polymorphism) or one lookup table."
    }
}

/// One `switch` statement, where it is, and its case labels.
struct SwitchUse {
    let subject: String
    let path: String
    let line: Int
    let cases: Set<String>

    /// Groups switches on the same subject in the same language.
    var key: String { ProjectUnits.family(of: path) + ":" + subject }

    /// Lists every non-test file's `switch` statements.
    ///
    /// - Parameter index: The project's facts.
    /// - Returns: The statements.
    static func all(in index: ProjectIndex) -> [SwitchUse] {
        index.facts.keys.filter { !ProjectUnits.isIncidental($0, in: index) }.flatMap { path in
            (index.facts[path]?.module.structure.switches ?? []).map {
                SwitchUse(subject: $0.subject, path: path, line: $0.line, cases: Set($0.cases))
            }
        }
    }

    /// Keeps the statements that share enough case labels with one in another file.
    ///
    /// - Parameters:
    ///   - uses: Statements on one subject.
    ///   - minShared: The fewest shared case labels.
    /// - Returns: The related statements, sorted by path and line.
    static func related(_ uses: [SwitchUse], minShared: Int) -> [SwitchUse] {
        uses.filter { use in
            uses.contains { $0.path != use.path && $0.cases.intersection(use.cases).count >= minShared }
        }.sorted { ($0.path, $0.line) < ($1.path, $1.line) }
    }
}
