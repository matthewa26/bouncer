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

    /// Extracts a file's imports and exports for the project pass.
    ///
    /// - Parameter file: The file to read.
    /// - Returns: Its module facts, or `nil` if this analyzer doesn't extract them.
    /// - Throws: If the file can't be parsed.
    func moduleFacts(file: SourceFile) throws -> ModuleFacts?
}

extension LanguageAnalyzer {
    /// Analyzers without a parser contribute no module facts.
    ///
    /// - Parameter file: The file to read.
    /// - Returns: `nil`.
    public func moduleFacts(file: SourceFile) throws -> ModuleFacts? { nil }
}
