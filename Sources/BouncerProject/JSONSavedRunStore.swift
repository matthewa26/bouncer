import Foundation
import BouncerCore

/// Keeps the last `review`'s result in `.bouncer-cache/last-run.json` at the repo root.
public struct JSONSavedRunStore: Sendable {
    /// The saved run's file.
    public let location: URL

    /// Opens the store for a repo.
    ///
    /// - Parameter repoRoot: The repository root.
    public init(repoRoot: URL) {
        location = repoRoot.appendingPathComponent(".bouncer-cache").appendingPathComponent("last-run.json")
    }

    /// Reads the saved run.
    ///
    /// - Returns: The saved run, or `nil` if there is none.
    /// - Throws: If the file can't be read or decoded, or `SavedRunError` if its contents don't add up.
    public func load() throws -> SavedRun? {
        guard FileManager.default.fileExists(atPath: location.path) else { return nil }
        let data = try Data(contentsOf: location)
        return try JSONDecoder().decode(SavedRunDocument.self, from: data).savedRun()
    }

    /// Writes a run, replacing the saved one in one step so a reader never sees half a file.
    ///
    /// - Parameter run: The run.
    /// - Returns: The file's size in bytes.
    /// - Throws: If the cache directory or file can't be written.
    @discardableResult
    public func save(_ run: SavedRun) throws -> Int {
        try FileManager.default.createDirectory(
            at: location.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(SavedRunDocument(run))
        try data.write(to: location, options: .atomic)
        return data.count
    }

    /// Encodes with sorted keys, so the same run always writes the same bytes.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}
