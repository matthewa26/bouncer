import Foundation
import BouncerCore
import BouncerReporting

/// The files a `verify` call or a refresh names, sorted into those to analyze, those to drop, and those to skip.
struct VerifyTargets: Sendable {
    /// Files to analyze: they exist, and the scan's walk would list them.
    private(set) var analyzed: [URL] = []
    /// Repo-relative paths of files to drop from the result: they're gone, or the walk wouldn't list them.
    private(set) var removed: [String] = []
    /// Paths that exist but the walk wouldn't list, such as excluded files or files outside the scanned directory.
    private(set) var skipped: [String] = []
    /// The repo-relative paths of `analyzed`.
    private(set) var analyzedPaths: [String] = []

    /// Sorts files.
    ///
    /// - Parameters:
    ///   - urls: The files.
    ///   - plan: The scan whose walk decides which files it analyzes.
    init(_ urls: [URL], plan: ScanPlan) {
        Self.unique(urls).forEach { sort($0, plan: plan) }
    }

    /// Sorts one file.
    ///
    /// - Parameters:
    ///   - url: The file.
    ///   - plan: The scan whose walk decides which files it analyzes.
    private mutating func sort(_ url: URL, plan: ScanPlan) {
        let path = RepoPath.relative(url, to: plan.repoRoot)
        guard !plan.walker.admits(url) else {
            (analyzed, analyzedPaths) = (analyzed + [url], analyzedPaths + [path])
            return
        }
        removed.append(path)
        if FileManager.default.fileExists(atPath: url.path) { skipped.append(path) }
    }

    /// Drops repeated files, keeping the first of each.
    ///
    /// - Parameter urls: The files.
    /// - Returns: The files, each once.
    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}

/// What re-analyzing some files found.
struct Reanalysis: Sendable {
    /// Which files were analyzed, removed, and skipped.
    let targets: VerifyTargets
    /// Their per-file findings before.
    let before: [Finding]
    /// Their per-file findings after.
    let after: [Finding]

    /// How the findings changed.
    var delta: FindingDelta { FindingDelta(before: before, after: after) }
}
