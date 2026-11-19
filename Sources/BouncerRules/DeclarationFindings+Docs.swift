import BouncerCore

/// The doc-completeness rules: a structured doc comment that leaves out a parameter, the return value,
/// or what's thrown, and one that documents a parameter the signature doesn't have.
extension DeclarationFindings {
    /// Runs both doc-completeness rules.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including each rule's resolved settings.
    /// - Returns: The combined findings.
    static func documentationFindings(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let documented = summary.functions.compactMap { function in
            function.documentation.map { (function, $0, DocCommentParser.parse($0.text, style: $0.style)) }
        }.filter { $0.2.isStructured }
        return incompleteDocumentation(documented, file: file, context: context)
            + staleDocumentation(documented, file: file, context: context)
    }

    /// A function with a structured doc, its facts, and what its doc documents.
    typealias DocumentedFunction = (CollectedFunction, DocumentationFacts, ParsedDoc)

    /// Flags every structured doc comment that leaves out a parameter, the return value, or what's thrown.
    ///
    /// - Parameters:
    ///   - documented: The functions with structured docs.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per incomplete doc, listing everything it leaves out.
    private static func incompleteDocumentation(
        _ documented: [DocumentedFunction], file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        guard let settings = enabledSettings("incomplete-documentation", context: context) else { return [] }
        let checks = (returns: settings.parameters.bool("requireReturns", default: true),
                      throwing: settings.parameters.bool("requireThrows", default: true))
        return documented.compactMap { function, facts, doc in
            let missing = missingParts(facts, doc, checks: checks)
            guard !missing.isEmpty else { return nil }
            let message = "Doc comment for \"\(function.name)\" doesn't describe \(list(missing))."
            return finding("incomplete-documentation", function.startLine, message, settings.severity, file)
        }
    }

    /// Lists what a doc leaves out: each undocumented parameter, then the return value and errors.
    ///
    /// - Parameters:
    ///   - facts: The function's signature facts.
    ///   - doc: What its doc documents.
    ///   - checks: Whether the return value and errors must be documented, per `requireReturns`/`requireThrows`.
    /// - Returns: A phrase per missing part.
    private static func missingParts(
        _ facts: DocumentationFacts, _ doc: ParsedDoc, checks: (returns: Bool, throwing: Bool)
    ) -> [String] {
        let documented = Set(doc.parameterNames)
        let names = facts.parameters.filter { !$0.isVariadic && $0.names.isDisjoint(with: documented) }
            .map { "\"\($0.name)\"" }
        let parameters = names.count > 4 ? ["\(names.count) parameters (\(names.prefix(3).joined(separator: ", ")), …)"]
            : names.map { "parameter \($0)" }
        return parameters
            + (checks.returns && facts.returnsValue && !doc.documentsReturn ? ["the return value"] : [])
            + (checks.throwing && facts.throwsError && !doc.documentsThrows ? ["what it throws"] : [])
    }

    /// Flags every structured doc comment naming a parameter its function doesn't have.
    ///
    /// - Parameters:
    ///   - documented: The functions with structured docs.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per stale doc, listing every unknown name.
    private static func staleDocumentation(
        _ documented: [DocumentedFunction], file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        guard let settings = enabledSettings("stale-documentation", context: context) else { return [] }
        return documented.compactMap { function, facts, doc in
            let stale = staleNames(facts, doc)
            guard !stale.isEmpty else { return nil }
            let message = "Doc comment for \"\(function.name)\" describes \(list(stale)), not in its signature."
            return finding("stale-documentation", function.startLine, message, settings.severity, file)
        }
    }

    /// Lists the parameter names a doc describes that its function doesn't have.
    ///
    /// - Parameters:
    ///   - facts: The function's signature facts.
    ///   - doc: What its doc documents.
    /// - Returns: Each stale name, quoted; none if some parameter has no name to match.
    private static func staleNames(_ facts: DocumentationFacts, _ doc: ParsedDoc) -> [String] {
        guard !facts.hasUnnamedParameters else { return [] }
        let known = facts.parameters.reduce(into: Set<String>()) { $0.formUnion($1.names) }
        return doc.parameterNames.filter { !known.contains($0) }.map { "\"\($0)\"" }
    }

    /// Joins phrases into an English list: `a`, `a and b`, or `a, b, and c`.
    ///
    /// - Parameter items: The phrases.
    /// - Returns: The joined list.
    private static func list(_ items: [String]) -> String {
        guard items.count > 2 else { return items.joined(separator: " and ") }
        return items.dropLast().joined(separator: ", ") + ", and " + (items.last ?? "")
    }
}
