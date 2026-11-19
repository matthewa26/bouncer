import Foundation
import BouncerCore

/// Flags a type that can't stand in for an abstraction it claims: it implements a protocol, interface, or
/// abstract-class requirement only to throw or trap (`fatalError("not supported")`,
/// `throw new Error("Method not implemented.")`, `raise NotImplementedError`), or it overrides a project
/// class's method adding a precondition the parent's version doesn't have.
///
/// Only concrete types with no project subclasses are judged, so intermediate bases that trap to mean
/// "abstract" aren't. A refusal of a method a project class ancestor implements (or of any Swift
/// `override`) is `refused-bequest`'s, and a conformer stubbing most of a protocol is
/// `interface-segregation`'s; this rule reports neither. A narrowed precondition is a body that opens with
/// `precondition(…)` or `guard … else { fatalError() }` (Swift), `if (…) throw …` (TS/JS), or `assert …` or
/// `if …: raise …` (Python) when the parent's implementation doesn't open with one.
public struct LiskovSubstitutionRule: ProjectRule {
    public let id = "liskov-substitution"

    /// Creates the rule.
    public init() {}

    /// Flags each concrete type that refuses requirements or narrows overridden methods' preconditions.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph and facts.
    ///   - targets: Unused; each finding lands at the type or extension.
    ///   - context: Repo-wide state, with `interface-segregation`'s parameters for the conformers it reports.
    /// - Returns: One finding per offending type or extension.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let conformances = Conformances(index: index)
        let segregation = InterfaceSegregationRule.Limits(context)
        return conformances.units.compactMap { unit -> Finding? in
            let refused = refusals(of: unit, conformances, segregation)
            let narrowed = conformances.narrowedPreconditions(of: unit)
            guard !refused.isEmpty || !narrowed.isEmpty else { return nil }
            let message = Self.message(unit.decl.name, refused: refused, narrowed: narrowed)
            return ProjectFinding.make(id, unit.decl.path, unit.decl.fact.line, message, context)
        }
    }

    /// Lists a unit's requirements that only throw or trap, leaving out those another rule reports.
    ///
    /// - Parameters:
    ///   - unit: The conforming type or extension.
    ///   - conformances: The project's conformances.
    ///   - segregation: `interface-segregation`'s thresholds.
    /// - Returns: Each refused requirement as `Abstraction.method`.
    private func refusals(
        of unit: ConformingUnit, _ conformances: Conformances, _ segregation: InterfaceSegregationRule.Limits
    ) -> [String] {
        let refused = Set(unit.decl.fact.allRefused).subtracting(conformances.bequeathed(to: unit))
        return unit.abstractions.filter { segregation.stubs(of: unit, in: $0).isEmpty }.flatMap { abstraction in
            Conformances.requirements(of: abstraction).filter(refused.contains).map { "\(abstraction.name).\($0)" }
        }
    }

    /// Explains a substitution problem.
    ///
    /// - Parameters:
    ///   - name: The type's name.
    ///   - refused: Refused requirements, as `Abstraction.method`.
    ///   - narrowed: Overrides with a precondition the parent lacks, as `Parent.method`.
    /// - Returns: The message.
    private static func message(_ name: String, refused: [String], narrowed: [String]) -> String {
        var parts: [String] = []
        if !refused.isEmpty { parts.append("implements \(Self.calls(refused)) only to throw or trap") }
        if !narrowed.isEmpty { parts.append("adds a precondition to \(Self.calls(narrowed)) that the parent lacks") }
        return "\"\(name)\" " + parts.joined(separator: " and ") + ", so it can't stand in wherever its "
            + "supertype is expected (Liskov substitution). Implement the behavior, or don't claim the supertype."
    }

    /// Lists methods as calls, eliding all but the first five.
    ///
    /// - Parameter names: The methods, as `Type.method`.
    /// - Returns: A comma-separated list such as `Store.save(), Store.load()`.
    static func calls(_ names: [String]) -> String {
        ManySubclassesRule.list(names.map { $0 + "()" })
    }
}

/// Flags a protocol, interface, or abstract class with many requirements that a conformer implements mostly
/// as stubs (empty, or only throwing or trapping): the abstraction asks for more than its clients need.
///
/// A protocol is judged when it has at least `minRequirements` methods, and a conformer when it stubs at
/// least `minStubs` of them and at least `minShare` of all of them. Test files, whose doubles stub on
/// purpose, are skipped. Each protocol is reported once, naming its stubbing conformers.
public struct InterfaceSegregationRule: ProjectRule {
    public let id = "interface-segregation"

    /// Creates the rule.
    public init() {}

    /// The thresholds that make a conformer a stubber, shared with `liskov-substitution`, which leaves
    /// these conformers to this rule.
    struct Limits {
        let minRequirements: Int
        let minStubs: Int
        let minShare: Double

        /// Reads the thresholds from this rule's settings.
        ///
        /// - Parameter context: Repo-wide state.
        init(_ context: AnalysisContext) {
            let parameters = context.settings(for: "interface-segregation").parameters
            minRequirements = parameters.int("minRequirements", default: 5)
            minStubs = parameters.int("minStubs", default: 3)
            minShare = parameters.double("minShare", default: 0.5)
        }

        /// Lists the requirements of an abstraction a unit stubs, if they're enough to report.
        ///
        /// - Parameters:
        ///   - unit: The conforming type or extension.
        ///   - abstraction: One of its protocols, interfaces, or abstract classes.
        /// - Returns: The stubbed requirements, or none if the unit doesn't stub enough of them.
        func stubs(of unit: ConformingUnit, in abstraction: DeclaredType) -> [String] {
            let requirements = Conformances.requirements(of: abstraction)
            guard requirements.count >= minRequirements else { return [] }
            let stubbed = Set(unit.decl.fact.allRefused + unit.decl.fact.allEmpty)
            let stubs = requirements.filter(stubbed.contains)
            let isMost = Double(stubs.count) >= minShare * Double(requirements.count)
            return stubs.count >= minStubs && isMost ? stubs : []
        }
    }

    /// Flags each abstraction some conformer mostly stubs.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph and facts.
    ///   - targets: Unused; each finding lands at the abstraction.
    ///   - context: Repo-wide state, with `minRequirements`, `minStubs`, and `minShare`.
    /// - Returns: One finding per abstraction.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let stubbers = Self.stubbers(Conformances(index: index), limits: Limits(context))
        return Dictionary(grouping: stubbers) { $0.0.id }.values.map { group in
            ProjectFinding.make(id, group[0].0.path, group[0].0.fact.line, Self.message(group), context)
        }.sorted { ($0.filePath.path, $0.line) < ($1.filePath.path, $1.line) }
    }

    /// Lists every conformer that stubs enough of an abstraction.
    ///
    /// - Parameters:
    ///   - conformances: The project's conformances.
    ///   - limits: The thresholds.
    /// - Returns: Each abstraction, stubbing conformer's name, and number of stubs.
    private static func stubbers(_ conformances: Conformances, limits: Limits) -> [(DeclaredType, String, Int)] {
        conformances.units.flatMap { unit in
            unit.abstractions.compactMap { abstraction -> (DeclaredType, String, Int)? in
                let stubs = limits.stubs(of: unit, in: abstraction)
                return stubs.isEmpty ? nil : (abstraction, unit.decl.name, stubs.count)
            }
        }
    }

    /// Explains an abstraction its conformers stub.
    ///
    /// - Parameter group: The abstraction, each stubbing conformer, and how many requirements it stubs.
    /// - Returns: The message.
    private static func message(_ group: [(DeclaredType, String, Int)]) -> String {
        let abstraction = group[0].0, total = Conformances.requirements(of: abstraction).count
        let stubbers = ManySubclassesRule.list(group.map { "\($0.1) stubs \($0.2)" })
        return "\"\(abstraction.name)\" has \(total) requirements, and conformers implement most of them as "
            + "empty or throwing stubs (\(stubbers)); split it into smaller protocols that clients use whole."
    }
}

/// Flags a project subclass that adds no stored fields and overrides exactly one method of its project
/// parent, the template-method shape that a closure or strategy passed to the parent replaces. Off unless
/// configured. Deep hierarchies, the other half of "composition over inheritance", are `deep-inheritance`'s.
///
/// For Swift the method must be marked `override`; for TS/JS and Python a project ancestor must declare it.
/// Methods that only throw or do nothing are `refused-bequest`'s. Test files are skipped.
public struct SingleOverrideSubclassRule: ProjectRule {
    public let id = "single-override-subclass"

    /// Creates the rule.
    public init() {}

    /// Flags each subclass whose only addition is one override.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph and facts.
    ///   - targets: Unused; each finding lands at the subclass.
    ///   - context: Repo-wide state; the rule only runs when configured.
    /// - Returns: One finding per such subclass.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        guard context.ruleSettings[id]?.enabled == true else { return [] }
        let hierarchy = TypeHierarchy(index: index)
        let judged = hierarchy.types.filter { !ProjectUnits.isIncidental($0.path, in: index) }
        return judged.compactMap { type -> Finding? in
            guard let parent = hierarchy.trustedAncestors(of: type).first,
                  let method = Self.onlyOverride(of: type, hierarchy: hierarchy) else { return nil }
            return ProjectFinding.make(id, type.path, type.fact.line, Self.message(type, parent, method), context)
        }
    }

    /// Explains a one-override subclass.
    ///
    /// - Parameters:
    ///   - type: The subclass.
    ///   - parent: Its parent.
    ///   - method: The overriding method.
    /// - Returns: The message.
    private static func message(_ type: DeclaredType, _ parent: DeclaredType, _ method: String) -> String {
        "\"\(type.name)\" subclasses \"\(parent.name)\" only to override \(method)(); pass the varying behavior "
            + "to \"\(parent.name)\" (a closure or strategy) instead of subclassing."
    }

    /// Returns a class's only method if it has no fields and that method overrides a real implementation.
    ///
    /// - Parameters:
    ///   - type: The subclass.
    ///   - hierarchy: The project's types.
    /// - Returns: The overriding method's name, or `nil`.
    private static func onlyOverride(of type: DeclaredType, hierarchy: TypeHierarchy) -> String? {
        let fact = type.fact
        guard fact.kind.isClass, fact.fields.isEmpty, fact.methods.count == 1, let method = fact.methods.first,
              !(fact.allRefused + fact.allEmpty).contains(method) else { return nil }
        let declared = hierarchy.trustedAncestors(of: type).contains { $0.fact.methods.contains(method) }
        let overrides = type.path.hasSuffix(".swift") ? fact.overrides.contains(method) : declared
        return overrides ? method : nil
    }
}
