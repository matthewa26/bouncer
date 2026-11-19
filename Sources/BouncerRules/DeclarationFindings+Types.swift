import BouncerCore

/// Class-shape rules: too many methods or fields, data classes, and too many classes per file.
extension DeclarationFindings {
    /// A per-type limit on one `TypeShape` count.
    private struct ShapeLimit: Sendable {
        let ruleID: String
        let parameter: String
        let defaultLimit: Int
        let count: @Sendable (TypeShape) -> Int
        let noun: String
    }

    private static let shapeLimits = [
        ShapeLimit(
            ruleID: "too-many-methods", parameter: "maxMethods", defaultLimit: 20,
            count: { $0.methodCount }, noun: "methods"
        ),
        ShapeLimit(
            ruleID: "too-many-fields", parameter: "maxFields", defaultLimit: 15,
            count: { $0.fieldCount }, noun: "fields"
        )
    ]

    /// Runs every class-shape rule.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including each rule's resolved settings.
    /// - Returns: The combined findings.
    static func typeShapeFindings(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        shapeLimits.flatMap { shapeFindings($0, summary, file: file, context: context) }
            + dataClasses(summary, file: file, context: context)
            + tooManyTypes(summary, file: file, context: context)
    }

    /// Flags every type whose count of one kind of member exceeds a limit.
    ///
    /// - Parameters:
    ///   - limit: The rule and the member count it limits.
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per type over the limit.
    private static func shapeFindings(
        _ limit: ShapeLimit, _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: limit.ruleID)
        guard settings.enabled else { return [] }
        let maximum = settings.parameters.int(limit.parameter, default: limit.defaultLimit)
        return summary.types.compactMap { type in
            guard let value = type.shape.map(limit.count), value > maximum else { return nil }
            let message = "Type \"\(type.name)\" has \(value) \(limit.noun), over the \(maximum) limit."
            return finding(limit.ruleID, type.startLine, message, settings.severity, file)
        }
    }

    /// Flags every class that holds data but has no behavior: two or more fields and no methods.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per data class.
    private static func dataClasses(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: "data-class")
        guard settings.enabled else { return [] }
        return summary.types.filter { $0.shape.map(isDataClass) ?? false }.map { type in
            let message = "Class \"\(type.name)\" only holds data; move the behavior that uses it here, "
                + "or make it a struct or record."
            return finding("data-class", type.startLine, message, settings.severity, file)
        }
    }

    /// Reports whether a type's shape is a class holding two or more fields and no methods.
    ///
    /// - Parameter shape: The type's shape.
    /// - Returns: Whether it's a data class.
    private static func isDataClass(_ shape: TypeShape) -> Bool {
        shape.isClass && shape.methodCount == 0 && shape.fieldCount >= 2
    }

    /// Flags a file that declares more types than allowed.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: A single finding, or none.
    private static func tooManyTypes(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: "too-many-types")
        let limit = settings.parameters.int("maxTypes", default: 5)
        guard settings.enabled, summary.types.count > limit, let first = summary.types.first else { return [] }
        let message = "File declares \(summary.types.count) types, over the \(limit) limit; "
            + "give the larger ones their own files."
        return [finding("too-many-types", first.startLine, message, settings.severity, file)]
    }
}
