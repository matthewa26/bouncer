import Foundation
import BouncerConfig

/// The well-known file locations Bouncer reads and writes outside a repo.
enum BouncerPaths {
    /// The current user's home directory, which holds every global Bouncer file.
    ///
    /// Honors a non-empty `HOME`, as most CLIs do, so a run can be pointed at a scratch home; Foundation's
    /// `homeDirectoryForCurrentUser` ignores `HOME` on macOS, so it's only the fallback.
    static var home: URL {
        guard let override = ProcessInfo.processInfo.environment["HOME"], !override.isEmpty else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: override, isDirectory: true)
    }

    /// `~/.bouncer`, the global config file.
    static var globalConfig: URL {
        home.appendingPathComponent(".bouncer")
    }

    /// `~/.bouncer-trust.json`, the hooks trust store.
    static var trustStore: URL {
        home.appendingPathComponent(".bouncer-trust.json")
    }

    /// `~/.bouncer-update-check-cache.json`, the cached last update check result.
    static var updateCheckCache: URL {
        home.appendingPathComponent(".bouncer-update-check-cache.json")
    }

    /// `<repoRoot>/.bouncer`, a repository's own config file.
    ///
    /// - Parameter repoRoot: The repository root.
    /// - Returns: The repo-level config file's location.
    static func repoConfig(repoRoot: URL) -> URL {
        repoRoot.appendingPathComponent(".bouncer")
    }

    /// The named-profile store for a repo: `<repoRoot>/.bouncer-profiles`, then `~/.bouncer-profiles`.
    ///
    /// - Parameter repoRoot: The repository root.
    /// - Returns: A store searching the repo's and the user's profile directories.
    static func profileStore(repoRoot: URL) -> ProfileStore {
        ProfileStore(repoRoot: repoRoot, homeDirectory: home)
    }

    /// The files the setup wizard reads and writes for a repo.
    ///
    /// - Parameter repoRoot: The repository root.
    /// - Returns: The repo and global `.bouncer` files, and the repo's profile store.
    static func setupPaths(repoRoot: URL) -> SetupPaths {
        SetupPaths(
            repoConfig: repoConfig(repoRoot: repoRoot), globalConfig: globalConfig,
            store: profileStore(repoRoot: repoRoot)
        )
    }

    /// `<repoRoot>/.bouncer-baseline.json`, a repository's accepted-findings snapshot.
    ///
    /// - Parameter repoRoot: The repository root.
    /// - Returns: The baseline file's location.
    static func baseline(repoRoot: URL) -> URL {
        repoRoot.appendingPathComponent(".bouncer-baseline.json")
    }
}
