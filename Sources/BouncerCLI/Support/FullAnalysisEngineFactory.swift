import Foundation
import BouncerCore

/// Builds a baseline-free, coverage-free `AnalysisEngine` for `bouncer baseline update`.
enum FullAnalysisEngineFactory {
    /// Builds an engine that captures every current finding, with no baseline filtering.
    ///
    /// - Parameters:
    ///   - rootDirectory: The directory to analyze.
    ///   - repoRoot: The repository root, used for rule context and relative paths.
    ///   - resolution: The resolved config layers.
    /// - Returns: A configured engine.
    static func make(rootDirectory: URL, repoRoot: URL, resolution: ConfigResolution) -> AnalysisEngine {
        let walker = RecursiveFileWalker(rootDirectory: rootDirectory, excludeGlobs: resolution.merged.exclude ?? [])
        let context = AnalysisContext(repoRoot: repoRoot, ruleSettings: resolution.merged.resolvedRuleSettings())
        return AnalysisEngine(
            fileProvider: walker, contentsProvider: FileSystemContentsProvider(),
            knownAnalyzers: AnalyzerFactory.makeKnownAnalyzers(),
            fallbackAnalyzer: AnalyzerFactory.makeFallbackAnalyzer(), context: context,
            project: ProjectPassFactory.make(index: walker, repoRoot: repoRoot)
        )
    }
}
