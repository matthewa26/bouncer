import SwiftTreeSitter
import BouncerCore
import BouncerRules

/// Analyzes a file using a real tree-sitter parse tree, rather than heuristics.
///
/// Runs the same generic line-based rules every other language shares (via
/// `LanguageProfile`) plus a set of AST-exact rules computed from the parse
/// tree instead of approximated from indentation, matching the pattern
/// `SwiftSyntaxAnalyzer` already established for Swift.
public struct TreeSitterAnalyzer: LanguageAnalyzer {
    public let supportedLanguage: BouncerCore.Language
    private let spec: TreeSitterLanguageSpec

    /// Creates a tree-sitter analyzer for one language.
    ///
    /// - Parameter spec: The language's tree-sitter node types and conventions.
    public init(spec: TreeSitterLanguageSpec) {
        self.supportedLanguage = spec.coreLanguage
        self.spec = spec
    }

    /// Parses a file and runs every generic and AST-based rule against it.
    ///
    /// - Parameters:
    ///   - file: The file to analyze.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The combined findings.
    /// - Throws: `TreeSitterAnalyzerError.parseFailed` if the parser produces no tree.
    public func analyze(file: SourceFile, context: AnalysisContext) throws -> [Finding] {
        let summary = try buildSummary(for: file)
        return genericFindings(file: file, context: context) + astFindings(summary, file: file, context: context)
    }

    /// Parses the file and collects its declaration summary.
    ///
    /// - Parameter file: The file to parse.
    /// - Returns: The collected summary.
    /// - Throws: `TreeSitterAnalyzerError.parseFailed` if parsing fails.
    private func buildSummary(for file: SourceFile) throws -> DeclarationSummary {
        let parser = Parser()
        try parser.setLanguage(spec.language)
        guard let tree = parser.parse(file.contents), let root = tree.rootNode else {
            throw TreeSitterAnalyzerError.parseFailed
        }
        return TreeSitterSummaryBuilder(spec: spec, source: file.contents).build(root: root)
    }

    /// Runs the language-agnostic heuristic rules shared with every other language.
    ///
    /// - Parameters:
    ///   - file: The file to analyze.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The combined findings from the shared rules.
    private func genericFindings(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let profile = LanguageProfiles.profile(for: spec.coreLanguage)
        let rules: [Rule] = [
            FileLengthRule(profile: profile), LongLineRule(), TodoDensityRule(),
            DuplicateBlockRule(), TrailingWhitespaceRule(), SecretPatternRule(), DeepNestingRule()
        ]
        let customRules = CustomRuleFactory.makeRules(from: profile.extraPatternRules)
        return (rules + customRules).flatMap { $0.evaluate(file: file, context: context) }
    }

    /// Runs every shared AST-based rule against a collected declaration summary.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's parse tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The combined findings from every AST-based rule.
    private func astFindings(_ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext) -> [Finding] {
        let naming = NamingPatterns(function: spec.functionNamePattern, type: spec.typeNamePattern)
        return DeclarationFindings.all(summary, file: file, context: context, naming: naming)
    }
}

/// An error analyzing a file with tree-sitter.
public enum TreeSitterAnalyzerError: Error {
    case parseFailed
}
