import Foundation

/// Resolves a `BouncerConfig` from every layer: a bundled profile, `~/.bouncer`, and a repo's `.bouncer`.
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
    ///   - globalPath: `~/.bouncer`'s location.
    ///   - repoRoot: The repository root, if analysis is running inside one.
    ///   - profileName: A bundled profile name to apply beneath everything else, if any.
    /// - Returns: The fully merged config.
    /// - Throws: If a config file exists but isn't valid JSON.
    public func load(globalPath: URL, repoRoot: URL?, profileName: String?) throws -> BouncerConfig {
        var config = BundledProfiles.profile(named: profileName)
        config = config.merging(try readIfExists(globalPath))
        if let repoRoot {
            config = config.merging(try readIfExists(repoRoot.appendingPathComponent(".bouncer")))
        }
        return config
    }

    /// Reads and decodes a `.bouncer` file, if it exists.
    ///
    /// - Parameter path: The file's location.
    /// - Returns: The decoded config, or `BouncerConfig.empty` if the file doesn't exist.
    /// - Throws: If the file exists but isn't valid JSON.
    private func readIfExists(_ path: URL) throws -> BouncerConfig {
        guard fileManager.fileExists(atPath: path.path) else { return .empty }
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(BouncerConfig.self, from: data)
    }
}
