import SwiftSyntax
import SwiftParser
import BouncerCore
import BouncerRules

/// Analyzes Swift files using a real syntax tree, rather than heuristics.
///
/// Runs the same generic line-based rules every other language shares (via
/// `LanguageProfile`) plus a set of Swift-specific rules computed exactly
/// from the parsed tree instead of approximated from indentation.
public struct SwiftSyntaxAnalyzer: LanguageAnalyzer {
    public let supportedLanguage: Language = .swift
    private static let profile = LanguageProfile(lineCommentPrefixes: ["//"])

    /// Creates a Swift syntax analyzer.
    public init() {}

    /// Parses a file and runs every generic and Swift-specific rule against it.
    ///
    /// - Parameters:
    ///   - file: The Swift file to analyze.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The combined findings.
    public func analyze(file: SourceFile, context: AnalysisContext) throws -> [Finding] {
        let tree = Parser.parse(source: file.contents)
        let converter = SourceLocationConverter(fileName: file.path.path, tree: tree)
        let builder = SwiftDeclarationSummaryBuilder(converter: converter)
        builder.walk(tree)
        let summary = builder.summary()
        return genericFindings(file: file, context: context) + astFindings(summary, file: file, context: context)
    }

    /// Runs the language-agnostic heuristic rules shared with every other language.
    ///
    /// - Parameters:
    ///   - file: The file to analyze.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The combined findings from the shared rules.
    private func genericFindings(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let rules: [Rule] = [
            FileLengthRule(profile: Self.profile), LongLineRule(), TodoDensityRule(),
            DuplicateBlockRule(), TrailingWhitespaceRule(), SecretPatternRule(), DeepNestingRule()
        ]
        return rules.flatMap { $0.evaluate(file: file, context: context) }
    }

    private typealias ASTRule = @Sendable (SwiftDeclarationSummary, SourceFile, AnalysisContext) -> [Finding]

    /// Every AST-based Swift rule, run in this order against a collected declaration summary.
    private static let astRules: [ASTRule] = [
        SwiftASTFindings.forceUnwrap, SwiftASTFindings.forceTry, SwiftASTFindings.longFunction,
        SwiftASTFindings.cyclomaticComplexity, SwiftASTFindings.missingDocumentation, SwiftASTFindings.namingConvention,
        SwiftASTFindings.highCoupling, SwiftASTFindings.switchOnTypeSmell, SwiftASTFindings.godClass
    ]

    /// Runs every AST-based Swift rule against a collected declaration summary.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The combined findings from every AST-based rule.
    private func astFindings(
        _ summary: SwiftDeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        Self.astRules.flatMap { $0(summary, file, context) }
    }
}
