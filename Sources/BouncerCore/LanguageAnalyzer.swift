/// Produces findings for one language, by whatever means suit it best.
///
/// `BouncerSwiftAnalyzer` implements this with a real syntax tree; every other
/// language goes through `BouncerHeuristicAnalyzer`'s line-based checks. Both
/// conform to the same protocol so the engine never needs to know which kind
/// of analysis a given file received.
public protocol LanguageAnalyzer: Sendable {
    /// The language this analyzer handles.
    var supportedLanguage: Language { get }

    /// Analyzes a file and returns every finding produced by its rules.
    ///
    /// - Parameters:
    ///   - file: The file to analyze.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: Zero or more findings.
    /// - Throws: If the file couldn't be parsed or read as this language.
    func analyze(file: SourceFile, context: AnalysisContext) throws -> [Finding]
}
