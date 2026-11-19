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
        genericFindings(file: file, context: context)
            + DeclarationFindings.all(summarize(file), file: file, context: context, naming: Self.naming)
    }

    /// Reads a Swift file's imports, by module name, for the project pass.
    ///
    /// - Parameter file: The file to read.
    /// - Returns: Its imports; Swift exports aren't tracked yet.
    public func moduleFacts(file: SourceFile) throws -> ModuleFacts? {
        let tree = Parser.parse(source: file.contents)
        let converter = SourceLocationConverter(fileName: file.path.path, tree: tree)
        let declarations = tree.statements.compactMap { $0.item.as(ImportDeclSyntax.self) }
        let imports = declarations.compactMap { node -> ImportFact? in
            guard let module = node.path.first?.name.text else { return nil }
            let line = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
            return ImportFact(specifier: module, line: line)
        }
        return ModuleFacts(imports: imports)
    }

    /// Parses a file and collects everything the shared AST rules need from it.
    ///
    /// - Parameter file: The Swift file.
    /// - Returns: Its declaration summary.
    private func summarize(_ file: SourceFile) -> DeclarationSummary {
        let tree = Parser.parse(source: file.contents)
        let converter = SourceLocationConverter(fileName: file.path.path, tree: tree)
        let builder = SwiftDeclarationSummaryBuilder(converter: converter)
        builder.walk(tree)
        let markers = SwiftMarkerCollector(converter: converter)
        markers.walk(tree)
        let names = SwiftNameCollector(converter: converter)
        names.walk(tree)
        return builder.summary(markers: markers.markers, names: names)
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
