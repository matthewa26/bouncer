import Foundation
import BouncerCore
import BouncerConfig
import BouncerProject

/// Builds the engine's project pass: the files to index, the repo's facts cache, and the project rules.
enum ProjectPassFactory {
    /// Builds a project pass over a set of files.
    ///
    /// - Parameters:
    ///   - index: The files to index.
    ///   - repoRoot: The repository root, where `.bouncer-cache/` lives.
    /// - Returns: The project pass.
    static func make(index: TargetFileProvider, repoRoot: URL) -> ProjectPhase {
        ProjectPhase(indexProvider: index, store: JSONFactsStore(repoRoot: repoRoot), analyzer: ProjectRules())
    }

    /// The files `check` indexes: the whole repo when `project.inCheck` is on, otherwise none.
    ///
    /// - Parameters:
    ///   - repoRoot: The repository root.
    ///   - config: The merged config.
    /// - Returns: A walker over the repo honoring `exclude`, or `nil` when project rules are off in `check`.
    static func checkIndex(repoRoot: URL, config: BouncerConfig) -> TargetFileProvider? {
        guard config.project?.inCheck == true else { return nil }
        return RecursiveFileWalker(rootDirectory: repoRoot, excludeGlobs: config.exclude ?? [])
    }
}
