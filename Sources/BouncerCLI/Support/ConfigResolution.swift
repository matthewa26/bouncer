import Foundation
import BouncerConfig

/// Every config layer a subcommand needs: the raw layers (for hooks trust-gating) and the merge.
struct ConfigResolution {
    let rawGlobal: BouncerConfig
    let rawRepo: BouncerConfig
    let merged: BouncerConfig
}

/// Resolves `.bouncer` config for one subcommand invocation.
enum ConfigResolver {
    /// Loads and merges every config layer for a run.
    ///
    /// - Parameters:
    ///   - repoRoot: The repository root, or the current directory if not in a repo.
    ///   - profile: A bundled profile name to apply as the base layer, such as `"kirby"`.
    ///   - explicitPath: An explicit `--config` path, replacing the layered resolution.
    /// - Returns: The raw layers and their merge.
    /// - Throws: If a config file exists but isn't valid JSON.
    static func resolve(repoRoot: URL, profile: String?, explicitPath: String?) throws -> ConfigResolution {
        if let explicitPath {
            return try resolveExplicit(path: explicitPath, profile: profile)
        }
        let loader = ConfigLoader()
        let rawGlobal = try readRaw(loader: loader, path: BouncerPaths.globalConfig)
        let rawRepo = try readRaw(loader: loader, path: BouncerPaths.repoConfig(repoRoot: repoRoot))
        let merged = try loader.load(globalPath: BouncerPaths.globalConfig, repoRoot: repoRoot, profileName: profile)
        return ConfigResolution(rawGlobal: rawGlobal, rawRepo: rawRepo, merged: merged)
    }

    /// Resolves config from a single explicit path, with the profile applied beneath it.
    ///
    /// - Parameters:
    ///   - path: The explicit config file's path.
    ///   - profile: A bundled profile name to apply as the base layer.
    /// - Returns: The resolved config, treated as both the "global" and merged layer.
    /// - Throws: If the file isn't valid JSON.
    private static func resolveExplicit(path: String, profile: String?) throws -> ConfigResolution {
        let loader = ConfigLoader()
        let explicit = try readRaw(loader: loader, path: URL(fileURLWithPath: path))
        let merged = BundledProfiles.profile(named: profile).merging(explicit)
        return ConfigResolution(rawGlobal: explicit, rawRepo: .empty, merged: merged)
    }

    /// Reads one config file without merging, or an empty config if it doesn't exist.
    ///
    /// - Parameters:
    ///   - loader: The loader to delegate the single-file read to.
    ///   - path: The file to read.
    /// - Returns: The decoded config, or `BouncerConfig.empty`.
    /// - Throws: If the file exists but isn't valid JSON.
    private static func readRaw(loader: ConfigLoader, path: URL) throws -> BouncerConfig {
        try loader.load(globalPath: path, repoRoot: nil, profileName: nil)
    }
}
