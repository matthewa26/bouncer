import BouncerCore
import BouncerHeuristicAnalyzer
import BouncerSwiftAnalyzer
import BouncerTreeSitterAnalyzer

/// Builds the language-to-analyzer mapping every subcommand's engine uses.
enum AnalyzerFactory {
    private static let heuristicLanguages: [Language] = [
        .zsh, .bash, .powershell, .cpp, .java, .sql, .c
    ]

    /// Builds an analyzer for every language with dedicated support.
    ///
    /// - Returns: The real-AST analyzers (Swift, Python, Go, TS, JS, Objective-C, Rust, PHP), plus a heuristic one per
    ///   other language.
    static func makeKnownAnalyzers() -> [Language: LanguageAnalyzer] {
        var analyzers: [Language: LanguageAnalyzer] = [.swift: SwiftSyntaxAnalyzer()]
        for analyzer in makeTreeSitterAnalyzers() { analyzers[analyzer.supportedLanguage] = analyzer }
        for language in heuristicLanguages { analyzers[language] = HeuristicAnalyzer(language: language) }
        return analyzers
    }

    /// Builds the tree-sitter analyzers. Objective-C files that fail to parse widely, as Objective-C++ does,
    /// fall back to the heuristic analyzer.
    ///
    /// - Returns: One analyzer per tree-sitter grammar.
    private static func makeTreeSitterAnalyzers() -> [TreeSitterAnalyzer] {
        [TreeSitterLanguageSpec.python, .go, .typescript, .javascript, .rust, .php].map { TreeSitterAnalyzer(spec: $0) }
            + [TreeSitterAnalyzer(spec: .objc, fallback: HeuristicAnalyzer(language: .objc))]
    }

    /// Builds the fallback analyzer used for any unrecognized language.
    ///
    /// - Returns: A heuristic analyzer that resolves its profile from the file's own language.
    static func makeFallbackAnalyzer() -> LanguageAnalyzer {
        HeuristicAnalyzer(language: .other(""))
    }
}
