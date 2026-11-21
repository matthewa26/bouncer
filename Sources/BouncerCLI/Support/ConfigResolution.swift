import Foundation
import BouncerConfig

/// Every config layer a subcommand needs: the raw layers (for hooks trust-gating) and the merge.
struct ConfigResolution {
    let rawGlobal: BouncerConfig
    let rawRepo: BouncerConfig
    let merged: BouncerConfig
}

/// Resolves `.bouncer` config for one subcommand invocation.
///
/// The profile is resolved here, not by each subcommand: `--profile` wins, then the repo `.bouncer`'s
/// `"profile"` key, then `~/.bouncer`'s (or, with `--config`, the explicit file's key). See `ConfigLoader`.
enum ConfigResolver {
    /// Loads and merges every config layer for a run.
    ///
    /// - Parameters:
    ///   - repoRoot: The repository root, or the current directory if not in a repo.
    ///   - profile: A `--profile` name to apply as the base layer, such as `"kirby"`.
    ///   - explicitPath: An explicit `--config` path, replacing the two file layers.
    /// - Returns: The raw layers and their merge.
    /// - Throws: If a config file exists but isn't valid JSON, or the profile can't be resolved.
    static func resolve(repoRoot: URL, profile: String?, explicitPath: String?) throws -> ConfigResolution {
        let globalPath = BouncerPaths.globalConfig
        let layers = try explicitPath.map { try explicitLayers(path: $0, repoRoot: repoRoot, profile: profile) }
            ?? ConfigLoader().loadLayers(globalPath: globalPath, repoRoot: repoRoot, profileName: profile)
        return ConfigResolution(rawGlobal: layers.global, rawRepo: layers.repo, merged: layers.merged)
    }

    /// Resolves config from a single explicit path, with the profile applied beneath it.
    ///
    /// The explicit file stands in for both `~/.bouncer` and the repo's `.bouncer`, so it's reported as
    /// the "global" layer and its hooks run ungated, as before; profiles still resolve repo-then-global.
    ///
    /// - Parameters:
    ///   - path: The explicit config file's path.
    ///   - repoRoot: The repository root, for finding repo profile files.
    ///   - profile: A `--profile` name, overriding the explicit file's `"profile"` key.
    /// - Returns: The explicit file and its merge with the profile.
    /// - Throws: If the file isn't valid JSON, or the profile can't be resolved.
    private static func explicitLayers(path: String, repoRoot: URL, profile: String?) throws -> ConfigLayers {
        try ConfigLoader().loadExplicit(
            path: URL(fileURLWithPath: path), profileName: profile, store: BouncerPaths.profileStore(repoRoot: repoRoot)
        )
    }
}
