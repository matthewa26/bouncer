import BouncerCore
import BouncerHeuristicAnalyzer
import BouncerSwiftAnalyzer
import BouncerTreeSitterAnalyzer

/// Builds the language-to-analyzer mapping every subcommand's engine uses.
enum AnalyzerFactory {
    private static let heuristicLanguages: [Language] = [
        .zsh, .bash, .powershell, .typescript, .javascript, .cpp, .java, .sql, .c
    ]

    /// Builds an analyzer for every language with dedicated support.
    ///
    /// - Returns: Swift's and Python's/Go's real-AST analyzers, plus a heuristic analyzer per other language.
    static func makeKnownAnalyzers() -> [Language: LanguageAnalyzer] {
        var analyzers: [Language: LanguageAnalyzer] = [
            .swift: SwiftSyntaxAnalyzer(),
            .python: TreeSitterAnalyzer(spec: .python),
            .go: TreeSitterAnalyzer(spec: .go)
        ]
        for language in heuristicLanguages { analyzers[language] = HeuristicAnalyzer(language: language) }
        return analyzers
    }

    /// Builds the fallback analyzer used for any unrecognized language.
    ///
    /// - Returns: A heuristic analyzer that resolves its profile from the file's own language.
    static func makeFallbackAnalyzer() -> LanguageAnalyzer {
        HeuristicAnalyzer(language: .other(""))
    }
}
