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
    /// Analyzes a file whose parse fails too widely to trust, for a grammar whose `CDeclarationSpec` sets
    /// `maxErrorShare`.
    private let fallback: LanguageAnalyzer?

    /// Creates a tree-sitter analyzer for one language.
    ///
    /// - Parameters:
    ///   - spec: The language's tree-sitter node types and conventions.
    ///   - fallback: Analyzes a file that fails to parse past the grammar's `maxErrorShare`, such as
    ///     Objective-C++ in the Objective-C grammar; `nil` always uses the tree.
    public init(spec: TreeSitterLanguageSpec, fallback: LanguageAnalyzer? = nil) {
        self.supportedLanguage = spec.coreLanguage
        self.spec = spec
        self.fallback = fallback
    }

    /// Parses a file and runs every generic and AST-based rule against it.
    ///
    /// - Parameters:
    ///   - file: The file to analyze.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The combined findings.
    /// - Throws: `TreeSitterAnalyzerError.parseFailed` if the parser produces no tree.
    public func analyze(file: SourceFile, context: AnalysisContext) throws -> [Finding] {
        let root = try parse(file)
        if let fallback = fallback(for: root) { return try fallback.analyze(file: file, context: context) }
        return findings(root: root, file: file, context: context)
    }

    /// Analyzes a file and reads its module facts from a single parse.
    ///
    /// - Parameters:
    ///   - file: The file to analyze.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The file's findings and module facts.
    /// - Throws: `TreeSitterAnalyzerError.parseFailed` if parsing fails.
    public func analyzeWithFacts(file: SourceFile, context: AnalysisContext) throws -> FileAnalysis {
        let root = try parse(file)
        let found = try fallback(for: root)?.analyze(file: file, context: context)
            ?? findings(root: root, file: file, context: context)
        return FileAnalysis(findings: found, facts: facts(root: root, file: file))
    }

    /// Parses a file and reads its imports and exports, for the project pass.
    ///
    /// - Parameter file: The file to read.
    /// - Returns: Its module facts, or `nil` for a language without an extractor.
    /// - Throws: `TreeSitterAnalyzerError.parseFailed` if parsing fails.
    public func moduleFacts(file: SourceFile) throws -> ModuleFacts? {
        spec.moduleFacts == nil ? nil : facts(root: try parse(file), file: file)
    }

    /// Runs every rule over an already-parsed file.
    ///
    /// - Parameters:
    ///   - root: The file's parse tree.
    ///   - file: The file.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The combined findings.
    private func findings(root: Node, file: SourceFile, context: AnalysisContext) -> [Finding] {
        let unused = spec.deadCode?.unusedDeclarations(in: DeadCodeTree(root: root, file: file)) ?? []
        let summary = TreeSitterSummaryBuilder(spec: spec, source: file.contents).build(root: root, unused: unused)
        return genericFindings(file: file, context: context) + astFindings(summary, file: file, context: context)
    }

    /// Measures every function from a single parse.
    ///
    /// - Parameter file: The file to measure.
    /// - Returns: One measurement per function.
    /// - Throws: `TreeSitterAnalyzerError.parseFailed` if parsing fails.
    public func measureFunctions(file: SourceFile) throws -> [FunctionMeasure]? {
        let root = try parse(file)
        if let fallback = fallback(for: root) { return try fallback.measureFunctions(file: file) }
        let summary = TreeSitterSummaryBuilder(spec: spec, source: file.contents).build(root: root)
        let profile = LanguageProfiles.profile(for: spec.coreLanguage)
        return DeclarationFindings.measures(summary, file: file, profile: profile)
    }

    /// Reads module facts from an already-parsed file.
    ///
    /// - Parameters:
    ///   - root: The file's parse tree.
    ///   - file: The file, for node text.
    /// - Returns: Its facts, or `nil` without an extractor.
    private func facts(root: Node, file: SourceFile) -> ModuleFacts? {
        spec.moduleFacts?.facts(root: root) { node in
            Range(node.range, in: file.contents).map { String(file.contents[$0]) }
        }
    }

    /// Picks the fallback analyzer for a tree that failed to parse past the spec's limit.
    ///
    /// Imports still come from the tree, since `#import` lines parse even where the code around them doesn't.
    ///
    /// - Parameter root: The file's parse tree.
    /// - Returns: The fallback, or `nil` to analyze the tree.
    private func fallback(for root: Node) -> LanguageAnalyzer? {
        guard let fallback, let limit = spec.cDeclarations?.maxErrorShare else { return nil }
        return ParseQuality.errorShare(of: root, declarations: spec.cDeclarations) > limit ? fallback : nil
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
