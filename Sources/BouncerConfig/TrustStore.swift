import Foundation
import BouncerCore

/// Records which repos' `hooks` sections the user has explicitly trusted to run.
///
/// A repo-committed `.bouncer` can declare shell commands that would
/// otherwise auto-execute the moment anyone runs `bouncer check`/`review`
/// inside a freshly cloned copy. Modeled on direnv's `.envrc` allow-list: a
/// hash of the trusted content is stored, so any edit to the hooks changes
/// the hash and re-prompts.
public struct TrustStore {
    private let path: URL

    /// Creates a trust store backed by a JSON file.
    ///
    /// - Parameter path: The trust file's location, typically `~/.bouncer-trust.json`.
    public init(path: URL) {
        self.path = path
    }

    /// A stable hash of a hooks config's contents, used as the trust key.
    ///
    /// - Parameter hooks: The hooks config to hash.
    /// - Returns: A stable hex digest.
    public static func contentHash(of hooks: HooksConfig) -> String {
        let data = (try? JSONEncoder().encode(hooks)) ?? Data()
        return StableHash.hex(String(data: data, encoding: .utf8) ?? "")
    }

    /// Checks whether a repo's current hooks content is already trusted.
    ///
    /// - Parameters:
    ///   - repoPath: The repository's absolute path.
    ///   - hooksHash: The current hooks config's content hash.
    /// - Returns: Whether this exact hash was previously trusted for this repo.
    public func isTrusted(repoPath: String, hooksHash: String) -> Bool {
        (try? records())?[repoPath] == hooksHash
    }

    /// Records a repo's current hooks content as trusted.
    ///
    /// - Parameters:
    ///   - repoPath: The repository's absolute path.
    ///   - hooksHash: The hooks config's content hash to trust.
    /// - Throws: If the trust file can't be read or written.
    public func trust(repoPath: String, hooksHash: String) throws {
        var all = (try? records()) ?? [:]
        all[repoPath] = hooksHash
        try JSONEncoder().encode(all).write(to: path)
    }

    /// Reads every trusted repo path and its trusted hooks hash.
    ///
    /// - Returns: The stored trust records, or an empty dictionary if the file doesn't exist.
    /// - Throws: If the file exists but isn't valid JSON.
    private func records() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: path.path) else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: path))
    }
}
