import Foundation
import BouncerCore

/// Counts a repo's analyzable files, so setup can suggest how an agent session picks up edits.
enum RepoFileCount {
    /// Counts the files `review` would analyze: every file the walker lists under the repo, less the excludes
    /// the repo's and the user's `.bouncer` files configure (and any profile they select).
    ///
    /// - Parameter paths: The wizard's files; the repo root is the folder holding the repo's `.bouncer`.
    /// - Returns: The file count, or 0 if the repo can't be walked.
    static func analyzableFiles(paths: SetupPaths) -> Int {
        let repoRoot = paths.repoConfig.deletingLastPathComponent()
        let config = try? ConfigLoader().load(globalPath: paths.globalConfig, repoRoot: repoRoot, profileName: nil)
        let walker = RecursiveFileWalker(rootDirectory: repoRoot, excludeGlobs: config?.exclude ?? [])
        return (try? walker.targetFiles().count) ?? 0
    }
}
