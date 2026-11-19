import Foundation
import BouncerCore

/// Flags a module far from Robert Martin's main sequence, `A + I = 1`. Off unless configured.
///
/// Abstractness `A` is the share of a module's types that are protocols, interfaces, or abstract classes;
/// instability `I` is `unstable-dependency`'s, measured between modules. A stable module (low `I`) should be
/// abstract so it can be extended without change, and an unstable one concrete. Distance `|A + I − 1|` near
/// 1 means either the zone of pain (concrete and depended on) or the zone of uselessness (abstract and
/// unused). Modules are Swift targets, Go packages, and TS/JS/Python folders; test modules are skipped.
public struct MainSequenceDistanceRule: ProjectRule {
    public let id = "main-sequence-distance"

    /// Creates the rule.
    public init() {}

    /// Flags each module with at least `minTypes` types whose distance exceeds `maxDistance`.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph and facts.
    ///   - targets: Unused; each finding lands in the module's first file.
    ///   - context: Repo-wide state; the rule only runs when configured, with `minTypes` and `maxDistance`.
    /// - Returns: One finding per module off the main sequence.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        guard let settings = context.ruleSettings[id], settings.enabled else { return [] }
        let minTypes = settings.parameters.int("minTypes", default: 5)
        let maxDistance = settings.parameters.double("maxDistance", default: 0.7)
        let modules = UnitGraph(index: index)
        return modules.metrics(minTypes: minTypes).compactMap { metric in
            guard metric.distance > maxDistance else { return nil }
            return ProjectFinding.make(id, metric.file, 1, Self.message(metric, limit: maxDistance), context)
        }
    }

    /// Explains a module's distance from the main sequence.
    ///
    /// - Parameters:
    ///   - metric: The module's measurements.
    ///   - limit: The allowed distance.
    /// - Returns: The message.
    private static func message(_ metric: ModuleMetric, limit: Double) -> String {
        let zone = metric.abstractness + metric.instability < 1
            ? "it's concrete and depended on, so every change ripples outward (the zone of pain)"
            : "it's abstract and little used (the zone of uselessness)"
        return String(format: "%@ has abstractness %.2f and instability %.2f, a distance of %.2f from the main "
                      + "sequence (over %.2f): %@.", ProjectUnits.display(metric.unit), metric.abstractness,
                      metric.instability, metric.distance, limit, zone)
    }
}

/// One module's abstractness, instability, and distance from the main sequence.
struct ModuleMetric {
    let unit: String
    /// The module's first file, where its finding lands.
    let file: String
    let abstractness: Double
    let instability: Double

    /// The distance from the main sequence, `|A + I − 1|`.
    var distance: Double { abs(abstractness + instability - 1) }
}

/// The project's modules: each one's files and types, and the dependencies between modules.
struct UnitGraph {
    /// Each module's files, sorted.
    let files: [String: [String]]
    /// Each module's declared types' kinds, leaving out extensions.
    let types: [String: [TypeKind]]
    let dependencies: [String: Set<String>]
    let dependents: [String: Set<String>]

    /// Groups files into modules and lifts the file graph's edges to modules.
    ///
    /// - Parameter index: The project's dependency graph and facts.
    init(index: ProjectIndex) {
        let unitOf = ProjectUnits.units(in: index)
        files = Dictionary(grouping: unitOf.keys.sorted()) { unitOf[$0] ?? "" }
        types = files.mapValues { paths in
            paths.flatMap { index.facts[$0]?.module.structure.types ?? [] }.map(\.kind).filter { $0 != .extension }
        }
        let edges = Self.edges(index, unitOf: unitOf)
        dependencies = Dictionary(grouping: edges, by: \.from).mapValues { Set($0.map(\.to)) }
        dependents = Dictionary(grouping: edges, by: \.to).mapValues { Set($0.map(\.from)) }
    }

    /// Lifts the file graph's edges to edges between different modules.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph.
    ///   - unitOf: Each file's module.
    /// - Returns: One edge per import between modules.
    private static func edges(_ index: ProjectIndex, unitOf: [String: String]) -> [(from: String, to: String)] {
        let filesOfNode = index.filesOfNode
        return index.edges.compactMap { edge in
            guard let from = unitOf[edge.file], let file = filesOfNode[edge.to]?.first,
                  let to = unitOf[file], from != to else { return nil }
            return (from: from, to: to)
        }
    }

    /// Measures each non-test module with at least `minTypes` types and a known instability.
    ///
    /// - Parameter minTypes: The fewest types a module needs to be measured.
    /// - Returns: The measurements, sorted by module.
    func metrics(minTypes: Int) -> [ModuleMetric] {
        let instability = UnstableDependencyRule.instability(outgoing: dependencies, incoming: dependents)
        return types.keys.sorted().compactMap { unit in
            guard let kinds = types[unit], kinds.count >= minTypes, let stability = instability[unit],
                  let file = files[unit]?.first, !ProjectUnits.isTest(file) else { return nil }
            let abstractness = Double(kinds.filter(\.isAbstract).count) / Double(kinds.count)
            return ModuleMetric(unit: unit, file: file, abstractness: abstractness, instability: stability)
        }
    }
}

/// Flags a module whose function names mix synonyms for one action, such as `fetchUser` beside `getOrder`
/// and `loadInvoice`, reporting the less common verbs. Off unless configured.
///
/// Verb groups default to fetch/get/load/retrieve/read, create/make/build, delete/remove/destroy, and
/// update/modify; set `groups` to a list like `["fetch get load", "create make new"]` to replace them. (`new`
/// and `change` are left out by default because they're as often adjectives and nouns: `newFile`,
/// `changeSet`.) A function named only the verb, such as a builder's `build()`, doesn't count, since its
/// name usually comes from a protocol or its type's role, and neither do initializers, test files, names
/// a language or framework dictates (Swift result builders' `buildBlock`, `makeIterator`, SwiftUI's
/// `makeUIView`/`updateUIView`), and `ignoreNames`.
public struct InconsistentTerminologyRule: ProjectRule {
    public let id = "inconsistent-terminology"
    static let defaultGroups = [
        "fetch get load retrieve read", "create make build", "delete remove destroy", "update modify"
    ]
    static let dictatedNames = [
        "buildBlock", "buildExpression", "buildOptional", "buildEither", "buildArray", "buildLimitedAvailability",
        "buildFinalResult", "buildPartialBlock", "makeIterator", "makeUIView", "updateUIView", "makeNSView",
        "updateNSView", "makeUIViewController", "updateUIViewController", "makeCoordinator", "makeBody"
    ]

    /// Creates the rule.
    public init() {}

    /// Flags each minority verb per module and group.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph and facts.
    ///   - targets: Unused; each finding lands at the verb's first function.
    ///   - context: Repo-wide state; the rule only runs when configured, with `groups` and `ignoreNames`.
    /// - Returns: One finding per module, group, and minority verb.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        guard let settings = context.ruleSettings[id], settings.enabled else { return [] }
        let groups = settings.parameters.stringList("groups", default: Self.defaultGroups)
            .map { $0.split(separator: " ").map { $0.lowercased() } }
        let ignored = Set(Self.dictatedNames + settings.parameters.stringList("ignoreNames", default: []))
        let modules = UnitGraph(index: index)
        return modules.files.keys.sorted().flatMap { unit in
            let uses = VerbUses(files: modules.files[unit] ?? [], index: index, ignoring: ignored)
            return groups.flatMap { group in minorityFindings(uses, group: group, unit: unit, context: context) }
        }
    }

    /// Reports each verb in a group used less than the module's most common one.
    ///
    /// - Parameters:
    ///   - uses: The module's functions by leading verb.
    ///   - group: The synonyms.
    ///   - unit: The module.
    ///   - context: Repo-wide state.
    /// - Returns: One finding per minority verb.
    private func minorityFindings(
        _ uses: VerbUses, group: [String], unit: String, context: AnalysisContext
    ) -> [Finding] {
        let used = group.filter { uses.byVerb[$0] != nil }
        guard let top = used.max(by: { (uses.count($0), $1) < (uses.count($1), $0) }), used.count > 1 else { return [] }
        return used.filter { uses.count($0) < uses.count(top) }.compactMap { verb in
            guard let first = uses.byVerb[verb]?.first else { return nil }
            let message = Self.message(unit, top: top, minority: verb, uses: uses)
            return ProjectFinding.make(id, first.path, first.line, message, context)
        }
    }

    /// Explains a minority verb.
    ///
    /// - Parameters:
    ///   - unit: The module.
    ///   - top: The module's most common verb in the group.
    ///   - minority: The less common verb.
    ///   - uses: The module's functions by verb.
    /// - Returns: The message.
    private static func message(_ unit: String, top: String, minority: String, uses: VerbUses) -> String {
        let names = ManySubclassesRule.list(Set(uses.byVerb[minority]?.map(\.name) ?? []).sorted())
        return "\(ProjectUnits.display(unit)) names \(uses.count(top)) functions \"\(top)…\" but "
            + "\(uses.count(minority)) \"\(minority)…\" (\(names)); pick one verb for the same action."
    }
}

/// A module's functions grouped by the verb their names start with.
struct VerbUses {
    /// Each lowercased leading verb's functions, in path and line order.
    let byVerb: [String: [(name: String, path: String, line: Int)]]

    /// Reads each named function's leading word, leaving out initializers, bare verbs, ignored names, and
    /// test and generated files.
    ///
    /// - Parameters:
    ///   - files: The module's files.
    ///   - index: The project's facts.
    ///   - ignored: Function names to leave out.
    init(files: [String], index: ProjectIndex, ignoring ignored: Set<String> = []) {
        let functions = files.filter { !ProjectUnits.isIncidental($0, in: index) }.flatMap { path in
            (index.facts[path]?.module.structure.functions ?? [])
                .filter { WordAffix.words($0.name).count > 1 && !ignored.contains($0.name) }
                .map { (name: $0.name, path: path, line: $0.line) }
        }
        byVerb = Dictionary(grouping: functions) { Self.verb(of: $0.name) }
    }

    /// Counts a verb's distinct function names.
    ///
    /// - Parameter verb: The verb.
    /// - Returns: How many differently named functions start with it.
    func count(_ verb: String) -> Int {
        Set((byVerb[verb] ?? []).map(\.name)).count
    }

    /// Reads a name's leading word, in camel case or snake case.
    ///
    /// - Parameter name: The function name.
    /// - Returns: Its first word, lowercased; the whole name if it's one word.
    static func verb(of name: String) -> String {
        (WordAffix.words(String(name.drop { $0 == "_" })).first ?? "").lowercased()
    }
}
