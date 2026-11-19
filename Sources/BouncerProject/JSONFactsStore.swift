import Foundation
import BouncerCore

/// Caches module facts in `.bouncer-cache/facts.json` at the repo root, so unchanged files aren't re-parsed.
///
/// The file records a format version; a cache written by a different version is ignored and rebuilt.
public struct JSONFactsStore: FactsStore {
    private static let version = 1
    private let location: URL
    private let cached: [String: FileFacts]

    /// The on-disk format.
    private struct CacheFile: Codable {
        let version: Int
        let files: [FileFacts]
    }

    /// Opens the cache for a repo, loading whatever valid facts it already holds.
    ///
    /// - Parameter repoRoot: The repository root.
    public init(repoRoot: URL) {
        location = repoRoot.appendingPathComponent(".bouncer-cache").appendingPathComponent("facts.json")
        let file = (try? Data(contentsOf: location)).flatMap { try? JSONDecoder().decode(CacheFile.self, from: $0) }
        let files = file?.version == Self.version ? file?.files ?? [] : []
        cached = Dictionary(files.map { ($0.path, $0) }) { first, _ in first }
    }

    /// Returns cached facts if the file's content hash still matches.
    ///
    /// - Parameters:
    ///   - path: The repo-relative path.
    ///   - contentHash: The file's current content hash.
    /// - Returns: The cached facts, or `nil` on a miss.
    public func cachedFacts(path: String, contentHash: String) -> FileFacts? {
        cached[path].flatMap { $0.contentHash == contentHash ? $0 : nil }
    }

    /// Writes the full set of facts, replacing the previous cache.
    ///
    /// - Parameter facts: Every indexed file's facts.
    /// - Throws: If the cache directory or file can't be written.
    public func save(_ facts: [FileFacts]) throws {
        try FileManager.default.createDirectory(
            at: location.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let cache = CacheFile(version: Self.version, files: facts.sorted { $0.path < $1.path })
        try encoder.encode(cache).write(to: location)
    }
}
