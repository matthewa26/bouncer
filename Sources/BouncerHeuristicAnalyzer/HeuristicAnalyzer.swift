import BouncerCore
import BouncerRules

/// Analyzes a file using line-based heuristic rules rather than a real parser.
///
/// Backs every language except Swift, plus anything unrecognized - the
/// "best effort" analysis path the plan calls for.
public struct HeuristicAnalyzer: LanguageAnalyzer {
    public let supportedLanguage: Language
    private let registry: RuleRegistry

    /// Creates a heuristic analyzer for one language.
    ///
    /// - Parameters:
    ///   - language: The language this analyzer instance handles.
    ///   - registry: Builds the rules to run against files of this language.
    public init(language: Language, registry: RuleRegistry = HeuristicRuleRegistry()) {
        self.supportedLanguage = language
        self.registry = registry
    }

    /// Runs every applicable rule against a file.
    ///
    /// - Parameters:
    ///   - file: The file to analyze.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The combined findings from every rule.
    public func analyze(file: SourceFile, context: AnalysisContext) throws -> [Finding] {
        let rules = registry.rules(for: file.language, ruleSettings: context.ruleSettings)
        return rules.flatMap { $0.evaluate(file: file, context: context) }
    }

    /// Measures the file's indentation-delimited function blocks.
    ///
    /// - Parameter file: The file to measure.
    /// - Returns: One unnamed measurement per block, or `nil` if the language has no function pattern.
    public func measureFunctions(file: SourceFile) throws -> [FunctionMeasure]? {
        CyclomaticComplexityRule(profile: LanguageProfiles.profile(for: file.language)).measures(in: file)
    }
}
