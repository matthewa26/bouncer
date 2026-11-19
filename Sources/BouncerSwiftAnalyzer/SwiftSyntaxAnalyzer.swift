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
    private static let profile = LanguageProfiles.profile(for: .swift)
    private static let naming = NamingPatterns(function: "^[a-z_][A-Za-z0-9_]*$", type: "^[A-Z][A-Za-z0-9_]*$")

    /// Creates a Swift syntax analyzer.
    public init() {}

    /// Parses a file and runs every generic and Swift-specific rule against it.
    ///
    /// - Parameters:
    ///   - file: The Swift file to analyze.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The combined findings.
    public func analyze(file: SourceFile, context: AnalysisContext) throws -> [Finding] {
        findings(Parsed(file), context: context)
    }

    /// Analyzes a file and reads its module facts from a single parse.
    ///
    /// - Parameters:
    ///   - file: The Swift file to analyze.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The file's findings and module facts.
    public func analyzeWithFacts(file: SourceFile, context: AnalysisContext) throws -> FileAnalysis {
        let parsed = Parsed(file)
        return FileAnalysis(findings: findings(parsed, context: context), facts: SwiftModuleFacts.facts(of: parsed))
    }

    /// Runs every rule over an already-parsed file.
    ///
    /// - Parameters:
    ///   - parsed: The parsed file.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The combined findings.
    private func findings(_ parsed: Parsed, context: AnalysisContext) -> [Finding] {
        genericFindings(file: parsed.file, context: context)
            + DeclarationFindings.all(summarize(parsed), file: parsed.file, context: context, naming: Self.naming)
    }

    /// Reads a Swift file's module facts for the project pass.
    ///
    /// - Parameter file: The file to read.
    /// - Returns: Its imports and public declarations.
    public func moduleFacts(file: SourceFile) throws -> ModuleFacts? {
        SwiftModuleFacts.facts(of: Parsed(file))
    }

    /// Collects everything the shared AST rules need from an already-parsed file.
    ///
    /// - Parameter parsed: The parsed file.
    /// - Returns: Its declaration summary.
    private func summarize(_ parsed: Parsed) -> DeclarationSummary {
        let builder = SwiftDeclarationSummaryBuilder(converter: parsed.converter)
        builder.walk(parsed.tree)
        let markers = SwiftMarkerCollector(converter: parsed.converter)
        markers.walk(parsed.tree)
        let names = SwiftNameCollector(converter: parsed.converter)
        names.walk(parsed.tree)
        return builder.summary(markers: markers.markers, names: names, unused: Self.unusedDeclarations(in: parsed))
    }

    /// Finds the private symbols and parameters nothing in an already-parsed file uses.
    ///
    /// - Parameter parsed: The parsed file.
    /// - Returns: Its unused declarations, for the dead-code rules.
    private static func unusedDeclarations(in parsed: Parsed) -> [UnusedDeclaration] {
        let collector = SwiftDeadCodeCollector(converter: parsed.converter)
        collector.walk(parsed.tree)
        let uses = SwiftUseCollector()
        uses.walk(parsed.tree)
        return collector.unused(uses: uses.positions)
    }

    /// Runs the language-agnostic heuristic rules shared with every other language.
    ///
    /// - Parameters:
    ///   - file: The file to analyze.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The combined findings from the shared rules.
    private func genericFindings(file: SourceFile, context: AnalysisContext) -> [Finding] {
        TextRules.make(profile: Self.profile).flatMap { $0.evaluate(file: file, context: context) }
    }
}
