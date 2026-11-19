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

    /// Measures every function from a single parse.
    ///
    /// - Parameter file: The Swift file to measure.
    /// - Returns: One measurement per function.
    public func measureFunctions(file: SourceFile) throws -> [FunctionMeasure]? {
        DeclarationFindings.measures(summarize(Parsed(file)), file: file, profile: Self.profile)
    }

    /// Runs every rule over an already-parsed file.
    ///
    /// - Parameters:
    ///   - parsed: The parsed file.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The combined findings.
    private func findings(_ parsed: Parsed, context: AnalysisContext) -> [Finding] {
        genericFindings(file: parsed.file, context: context)
            + DeclarationFindings.all(
                summarize(parsed, optIns: Self.optInMarkers(context)), file: parsed.file, context: context,
                naming: Self.naming
            )
    }

    /// Lists the opt-in marker rules a config turns on, so only their walks run.
    ///
    /// - Parameter context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The enabled opt-in marker kinds.
    private static func optInMarkers(_ context: AnalysisContext) -> Set<MarkerKind> {
        Set(MarkerKind.allCases.filter { $0.isOptIn && context.ruleSettings[$0.ruleID]?.enabled == true })
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
    /// - Parameters:
    ///   - parsed: The parsed file.
    ///   - optIns: The opt-in marker rules to collect, such as `law-of-demeter`.
    /// - Returns: Its declaration summary.
    private func summarize(_ parsed: Parsed, optIns: Set<MarkerKind> = []) -> DeclarationSummary {
        let builder = Self.walk(SwiftDeclarationSummaryBuilder(converter: parsed.converter), over: parsed)
        let markers = Self.walk(SwiftMarkerCollector(converter: parsed.converter), over: parsed)
        let names = Self.walk(SwiftNameCollector(converter: parsed.converter), over: parsed)
        let shapes = Self.walk(SwiftShapeCollector(converter: parsed.converter), over: parsed)
        return builder.summary(
            markers: markers.markers + shapes.markers + Self.optInMarkers(optIns, in: parsed),
            names: names,
            shapes: shapes.facts(typedNames: names.typedNames), unused: Self.unusedDeclarations(in: parsed)
        )
    }

    /// Collects the enabled opt-in markers: each member chain's reach, for `law-of-demeter`, and each
    /// ask-then-tell `if`, for `tell-dont-ask`.
    ///
    /// - Parameters:
    ///   - kinds: The enabled opt-in marker kinds.
    ///   - parsed: The parsed file.
    /// - Returns: Their markers.
    private static func optInMarkers(_ kinds: Set<MarkerKind>, in parsed: Parsed) -> [CollectedMarker] {
        let chains = kinds.contains(.lawOfDemeter)
            ? walk(SwiftDemeterCollector(converter: parsed.converter), over: parsed).markers : []
        let asks = kinds.contains(.tellDontAsk)
            ? walk(SwiftTellDontAskCollector(converter: parsed.converter), over: parsed).markers : []
        return chains + asks
    }

    /// Walks a visitor over a whole parsed file.
    ///
    /// - Parameters:
    ///   - visitor: The visitor.
    ///   - parsed: The parsed file.
    /// - Returns: The visitor, after the walk.
    private static func walk<Visitor: SyntaxVisitor>(_ visitor: Visitor, over parsed: Parsed) -> Visitor {
        visitor.walk(parsed.tree)
        return visitor
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
