import Foundation
import BouncerCore

/// Class-design rules over a type's `TypeStructure`: WMC, the LCOM variants, TCC/LCC, lazy class, and
/// middle man.
extension DeclarationFindings {
    /// Runs every class-design rule.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including each rule's resolved settings.
    /// - Returns: The combined findings.
    static func classDesignFindings(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        weightedMethods(summary, file: file, context: context)
            + classCohesion(summary, file: file, context: context)
            + lazyClasses(summary, file: file, context: context)
            + middleMen(summary, file: file, context: context)
            + designSmellFindings(summary, file: file, context: context)
    }

    /// Lists the types with a measured structure, alongside it.
    ///
    /// - Parameter summary: The declarations collected from the file's syntax tree.
    /// - Returns: Each measured type and its structure.
    private static func structuredTypes(_ summary: DeclarationSummary) -> [(CollectedType, TypeStructure)] {
        summary.types.compactMap { type in type.structure.map { (type, $0) } }
    }

    /// Flags every type whose methods' cyclomatic complexities sum to more than `max` (WMC); test suites,
    /// which grow one simple method per test, are skipped.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per over-weighted type.
    private static func weightedMethods(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        guard let settings = enabledSettings("weighted-methods", context: context) else { return [] }
        let limit = settings.parameters.int("max", default: 50)
        return structuredTypes(summary).compactMap { type, structure in
            guard structure.weightedMethods > limit, !isTestTypeName(type.name) else { return nil }
            let message = "Type \"\(type.name)\" has weighted methods (WMC) \(structure.weightedMethods) across "
                + "\(structure.methodComplexities.count) methods, over the \(limit) limit."
            return finding("weighted-methods", type.startLine, message, settings.severity, file)
        }
    }

    /// Flags every type whose tight class cohesion (TCC) or loose class cohesion (LCC) is under its
    /// minimum; off unless configured.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per loosely connected type.
    private static func classCohesion(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        guard let settings = enabledSettings("class-cohesion", optIn: true, context: context) else { return [] }
        let limits = CohesionLimits(settings.parameters)
        return structuredTypes(summary).compactMap { type, structure in
            limits.violation(by: type, structure).map {
                finding("class-cohesion", type.startLine, $0, settings.severity, file)
            }
        }
    }

    /// The `class-cohesion` rule's minimums.
    private struct CohesionLimits {
        let tight: Double
        let loose: Double
        let methods: Int

        /// Reads the minimums from the rule's parameters.
        ///
        /// - Parameter parameters: The rule's parameters.
        init(_ parameters: RuleParameters) {
            tight = parameters.double("minTCC", default: 0.33)
            loose = parameters.double("minLCC", default: 0)
            methods = parameters.int("minMethods", default: 4)
        }

        /// Checks one type against the minimums.
        ///
        /// - Parameters:
        ///   - type: The type.
        ///   - structure: Its structure.
        /// - Returns: The finding message, or `nil` if it's cohesive enough or has too few stateful methods.
        func violation(by type: CollectedType, _ structure: TypeStructure) -> String? {
            guard let ratios = CohesionGraph.classCohesion(structure.methods, fields: structure.fieldNames),
                  ratios.methods >= methods, ratios.tight < tight || ratios.loose < loose else { return nil }
            return "Type \"\(type.name)\" has tight class cohesion \(percent(ratios.tight)) and loose class cohesion "
                + "\(percent(ratios.loose)) across \(ratios.methods) methods, under the minimums (TCC "
                + "\(percent(tight)), LCC \(percent(loose)))."
        }
    }

    /// Formats a ratio as a whole percentage.
    ///
    /// - Parameter ratio: A value from 0 to 1.
    /// - Returns: Its text, such as `25%`.
    private static func percent(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }

    /// Flags every plain type that does almost nothing: no fields, one branch-free instance method, and
    /// nothing else in its body; off unless configured. Public or exported types, types with a supertype,
    /// conformance, attribute, decorator, or generic parameter, types an extension in the file adds to, a
    /// lone dunder method such as `__repr__`, and test classes are skipped.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per lazy type.
    private static func lazyClasses(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        guard let settings = enabledSettings("lazy-class", optIn: true, context: context) else { return [] }
        return structuredTypes(summary).filter(isLazy).map { type, _ in
            let message = "Type \"\(type.name)\" holds no state and one trivial method; "
                + "make it a function, or fold it into its caller."
            return finding("lazy-class", type.startLine, message, settings.severity, file)
        }
    }

    /// Reports whether a type is a stateless wrapper around one branch-free method.
    ///
    /// - Parameter entry: The type and its structure.
    /// - Returns: Whether it's lazy.
    private static func isLazy(_ entry: (CollectedType, TypeStructure)) -> Bool {
        let (type, structure) = entry
        guard structure.isPlain, structure.isComplete, structure.fieldNames.isEmpty, type.memberCount == 1,
              structure.methodComplexities == [1], let method = structure.methods.first,
              !method.name.hasPrefix("__") else { return false }
        return !isTestTypeName(type.name)
    }

    /// Reports whether a type's name marks it as a test suite, such as `ParserTests` or `TestParser`.
    ///
    /// - Parameter name: The type's name.
    /// - Returns: Whether it's a test suite.
    static func isTestTypeName(_ name: String) -> Bool {
        DocCommentParser.matches(#"^Test|Tests?$|Spec$"#, name)
    }

    /// Flags every type where most methods only forward to a field's method of the same name, and at
    /// least `minDelegations` do.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per middle man.
    private static func middleMen(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        guard let settings = enabledSettings("middle-man", context: context) else { return [] }
        let minimum = settings.parameters.int("minDelegations", default: 3)
        return structuredTypes(summary).compactMap { type, structure in
            middleManMessage(type, structure, minimum: minimum).map {
                finding("middle-man", type.startLine, $0, settings.severity, file)
            }
        }
    }

    /// Checks whether a type is a middle man: complete in its body, with at least `minimum` methods that
    /// only forward, and more forwarding methods than not.
    ///
    /// - Parameters:
    ///   - type: The type.
    ///   - structure: Its structure.
    ///   - minimum: The fewest forwarding methods to report.
    /// - Returns: The finding message, or `nil`.
    private static func middleManMessage(_ type: CollectedType, _ structure: TypeStructure, minimum: Int) -> String? {
        let delegates = structure.methods.compactMap(\.delegate), total = structure.methods.count
        guard structure.isComplete, delegates.count >= minimum, delegates.count * 2 > total else { return nil }
        let targets = Set(delegates).sorted().map { "\"\($0)\"" }.joined(separator: ", ")
        return "Type \"\(type.name)\" only forwards \(delegates.count) of its \(total) methods to \(targets); "
            + "let callers use it directly."
    }
}
