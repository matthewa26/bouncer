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

    /// Parses a file and reads its imports and exports, for the project pass.
    ///
    /// - Parameter file: The file to read.
    /// - Returns: Its module facts, or `nil` for a language without an extractor.
    /// - Throws: `TreeSitterAnalyzerError.parseFailed` if parsing fails.
    public func moduleFacts(file: SourceFile) throws -> ModuleFacts? {
        guard let extractor = spec.moduleFacts else { return nil }
        let root = try parse(file)
        return extractor.facts(root: root) { node in
            Range(node.range, in: file.contents).map { String(file.contents[$0]) }
        }
    }

    /// Parses a file with its language's grammar.
    ///
    /// - Parameter file: The file to parse.
    /// - Returns: The parse tree's root.
    /// - Throws: `TreeSitterAnalyzerError.parseFailed` if the parser produces no tree.
    private func parse(_ file: SourceFile) throws -> Node {
        let parser = Parser()
        try parser.setLanguage(spec.grammar(forExtension: file.path.pathExtension))
        guard let tree = parser.parse(file.contents), let root = tree.rootNode else {
            throw TreeSitterAnalyzerError.parseFailed
        }
        return root
    }

    /// Parses the file and collects its declaration summary.
    ///
    /// - Parameter file: The file to parse.
    /// - Returns: The collected summary.
    /// - Throws: `TreeSitterAnalyzerError.parseFailed` if parsing fails.
    private func buildSummary(for file: SourceFile) throws -> DeclarationSummary {
        TreeSitterSummaryBuilder(spec: spec, source: file.contents).build(root: try parse(file))
    }

    /// Runs the language-agnostic heuristic rules shared with every other language.
    ///
    /// - Parameters:
    ///   - file: The file to analyze.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The combined findings from the shared rules.
    private func genericFindings(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let profile = LanguageProfiles.profile(for: spec.coreLanguage)
        return TextRules.make(profile: profile).flatMap { $0.evaluate(file: file, context: context) }
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
