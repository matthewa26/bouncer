import Foundation
import BouncerCore

/// Reads and writes a `Baseline` as JSON at `.bouncer-baseline.json`.
public struct JSONBaselineStore: BaselineStore {
    /// Creates a JSON-backed baseline store.
    public init() {}

    /// Loads a baseline from disk, or an empty one if the file doesn't exist.
    ///
    /// - Parameter path: The baseline file's location.
    /// - Returns: The loaded baseline.
    /// - Throws: If the file exists but isn't valid JSON.
    public func load(from path: URL) throws -> Baseline {
        guard FileManager.default.fileExists(atPath: path.path) else { return .empty }
        return try JSONDecoder().decode(Baseline.self, from: Data(contentsOf: path))
    }

    /// Writes a baseline to disk as JSON.
    ///
    /// - Parameters:
    ///   - baseline: The baseline to persist.
    ///   - path: The destination file.
    /// - Throws: If the file can't be written.
    public func write(_ baseline: Baseline, to path: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(baseline).write(to: path)
    }
}
