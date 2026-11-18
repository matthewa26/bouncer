import Foundation

/// The well-known file locations Bouncer reads and writes outside a repo.
enum BouncerPaths {
    /// `~/.bouncer`, the global config file.
    static var globalConfig: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".bouncer")
    }

    /// `~/.bouncer-trust.json`, the hooks trust store.
    static var trustStore: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".bouncer-trust.json")
    }

    /// `~/.bouncer-update-check-cache.json`, the cached last update check result.
    static var updateCheckCache: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".bouncer-update-check-cache.json")
    }

    /// `<repoRoot>/.bouncer`, a repository's own config file.
    ///
    /// - Parameter repoRoot: The repository root.
    /// - Returns: The repo-level config file's location.
    static func repoConfig(repoRoot: URL) -> URL {
        repoRoot.appendingPathComponent(".bouncer")
    }

    /// `<repoRoot>/.bouncer-baseline.json`, a repository's accepted-findings snapshot.
    ///
    /// - Parameter repoRoot: The repository root.
    /// - Returns: The baseline file's location.
    static func baseline(repoRoot: URL) -> URL {
        repoRoot.appendingPathComponent(".bouncer-baseline.json")
    }
}
