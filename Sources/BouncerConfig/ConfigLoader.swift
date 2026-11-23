import Foundation

/// Every config layer one resolution read, kept separate for callers that gate on a single layer.
public struct ConfigLayers: Sendable, Equatable {
    /// The profile applied as the base layer, if any.
    public let profileName: String?
    /// `~/.bouncer`, or the explicit `--config` file when one was given.
    public let global: BouncerConfig
    /// The repo's own `.bouncer`, or empty with an explicit `--config` file.
    public let repo: BouncerConfig
    /// Every layer merged: profile, then global, then repo.
    public let merged: BouncerConfig
}

/// Resolves a `BouncerConfig` from every layer: a profile, `~/.bouncer`, and a repo's `.bouncer`.
///
/// The profile's name comes from the CLI's `--profile` first, then the repo `.bouncer`'s `"profile"`, then
/// `~/.bouncer`'s. It resolves through `ProfileStore`: `<repoRoot>/.bouncer-profiles/<name>.json`, then
/// `~/.bouncer-profiles/<name>.json`, then a bundled preset; an unknown name is an error.
public struct ConfigLoader {
    private let fileManager: FileManager

    /// Creates a config loader.
    ///
    /// - Parameter fileManager: The file manager to read config files with.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Loads and merges every config layer, in increasing precedence order.
    ///
    /// - Parameters:
    ///   - globalPath: `~/.bouncer`'s location; its directory also holds the global `.bouncer-profiles`.
    ///   - repoRoot: The repository root, if analysis is running inside one.
    ///   - profileName: A `--profile` name, overriding any `"profile"` key in the config files.
    /// - Returns: The fully merged config.
    /// - Throws: If a config file exists but isn't valid JSON, or the profile can't be resolved.
    public func load(globalPath: URL, repoRoot: URL?, profileName: String?) throws -> BouncerConfig {
        try loadLayers(globalPath: globalPath, repoRoot: repoRoot, profileName: profileName).merged
    }

    /// Loads every config layer, keeping the raw file layers alongside their merge.
    ///
    /// - Parameters:
    ///   - globalPath: `~/.bouncer`'s location; its directory also holds the global `.bouncer-profiles`.
    ///   - repoRoot: The repository root, if analysis is running inside one.
    ///   - profileName: A `--profile` name, overriding any `"profile"` key in the config files.
    /// - Returns: The raw layers and their merge.
    /// - Throws: If a config file exists but isn't valid JSON, or the profile can't be resolved.
    public func loadLayers(globalPath: URL, repoRoot: URL?, profileName: String?) throws -> ConfigLayers {
        let global = try read(globalPath)
        let repo = try repoRoot.map { try read($0.appendingPathComponent(".bouncer")) } ?? .empty
        let store = ProfileStore(
            repoRoot: repoRoot, homeDirectory: globalPath.deletingLastPathComponent(), fileManager: fileManager
        )
        let name = Self.effectiveProfileName(cli: profileName, files: [repo, global])
        return try layers(profileName: name, store: store, global: global, repo: repo)
    }

    /// Loads one explicit `--config` file in place of `~/.bouncer` and the repo's `.bouncer`.
    ///
    /// The profile still applies beneath it, named by `--profile` or else by the explicit file's own
    /// `"profile"` key, and still resolves through `store`, so `--config` swaps the file layers only.
    ///
    /// - Parameters:
    ///   - path: The explicit config file.
    ///   - profileName: A `--profile` name, overriding the file's `"profile"` key.
    ///   - store: Where to resolve the profile.
    /// - Returns: The explicit file as the `global` layer, an empty `repo` layer, and their merge.
    /// - Throws: If the file isn't valid JSON, or the profile can't be resolved.
    public func loadExplicit(path: URL, profileName: String?, store: ProfileStore) throws -> ConfigLayers {
        let explicit = try read(path)
        let name = Self.effectiveProfileName(cli: profileName, files: [explicit])
        return try layers(profileName: name, store: store, global: explicit, repo: .empty)
    }

    /// Picks the profile name: the CLI's, else the first file layer's `"profile"` key.
    ///
    /// - Parameters:
    ///   - cli: The `--profile` value, if passed.
    ///   - files: The file layers, highest precedence first.
    /// - Returns: The profile name to apply, or `nil` for none.
    public static func effectiveProfileName(cli: String?, files: [BouncerConfig]) -> String? {
        cli ?? files.lazy.compactMap(\.profile).first
    }

    /// Reads and decodes a `.bouncer` file, if it exists, without applying its profile.
    ///
    /// - Parameter path: The file's location.
    /// - Returns: The decoded config, or `BouncerConfig.empty` if the file doesn't exist.
    /// - Throws: If the file exists but isn't valid JSON, or `ConfigError` if a setting is out of range.
    public func read(_ path: URL) throws -> BouncerConfig {
        guard fileManager.fileExists(atPath: path.path) else { return .empty }
        let data = try Data(contentsOf: path)
        let config = try JSONDecoder().decode(BouncerConfig.self, from: data)
        if let jobs = config.jobs, jobs < 1 { throw ConfigError.invalidJobs(path: path.path, value: jobs) }
        return config
    }

    /// Resolves the profile and merges it beneath the file layers.
    ///
    /// - Parameters:
    ///   - profileName: The effective profile name, if any.
    ///   - store: Where to resolve the profile.
    ///   - global: The global (or explicit) file layer.
    ///   - repo: The repo file layer.
    /// - Returns: The layers, with `merged.profile` set to the profile actually applied.
    /// - Throws: A `ProfileError`, or a decoding error from a profile file.
    private func layers(
        profileName: String?, store: ProfileStore, global: BouncerConfig, repo: BouncerConfig
    ) throws -> ConfigLayers {
        let base = try profileName.map(store.config(named:)) ?? .empty
        var merged = base.merging(global).merging(repo)
        merged.profile = profileName
        return ConfigLayers(profileName: profileName, global: global, repo: repo, merged: merged)
    }
}
