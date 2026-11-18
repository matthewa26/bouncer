import Foundation

/// A stable identity for a finding, used to recognize it across runs.
///
/// Uses a content hash of the offending line rather than its line number, so
/// the fingerprint survives unrelated edits elsewhere in the file.
public struct FindingFingerprint: Hashable, Codable, Sendable {
    public let ruleID: String
    public let relativePath: String
    public let contentHash: String

    /// Creates a fingerprint.
    ///
    /// - Parameters:
    ///   - ruleID: The rule that produced the finding.
    ///   - relativePath: The file's path relative to the repo root.
    ///   - contentHash: A stable hash of the offending content.
    public init(ruleID: String, relativePath: String, contentHash: String) {
        self.ruleID = ruleID
        self.relativePath = relativePath
        self.contentHash = contentHash
    }
}

/// A snapshot of findings accepted as pre-existing, so only new ones get reported.
public struct Baseline: Sendable, Codable {
    public let fingerprints: Set<FindingFingerprint>

    /// An empty baseline, equivalent to "nothing has been accepted yet."
    public static let empty = Baseline(fingerprints: [])

    /// Creates a baseline from a set of fingerprints.
    ///
    /// - Parameter fingerprints: The accepted findings' fingerprints.
    public init(fingerprints: Set<FindingFingerprint>) {
        self.fingerprints = fingerprints
    }

    /// Reports whether a fingerprint was already accepted into this baseline.
    ///
    /// - Parameter fingerprint: The fingerprint to check.
    /// - Returns: Whether the baseline already contains it.
    public func contains(_ fingerprint: FindingFingerprint) -> Bool {
        fingerprints.contains(fingerprint)
    }

    /// Builds the fingerprint a finding would have in a baseline.
    ///
    /// - Parameters:
    ///   - ruleID: The rule that produced the finding.
    ///   - relativePath: The file's path relative to the repo root.
    ///   - lineContent: The offending line's text.
    /// - Returns: A fingerprint stable across unrelated edits to the file.
    public static func fingerprint(ruleID: String, relativePath: String, lineContent: String) -> FindingFingerprint {
        let trimmed = lineContent.trimmingCharacters(in: .whitespaces)
        return FindingFingerprint(ruleID: ruleID, relativePath: relativePath, contentHash: StableHash.hex(trimmed))
    }
}

/// Reads and writes a `Baseline` to disk.
public protocol BaselineStore: Sendable {
    /// Loads a baseline from a file, or an empty one if it doesn't exist.
    ///
    /// - Parameter path: The baseline file's location.
    /// - Returns: The loaded baseline.
    /// - Throws: If the file exists but can't be parsed.
    func load(from path: URL) throws -> Baseline

    /// Writes a baseline to a file, overwriting any existing content.
    ///
    /// - Parameters:
    ///   - baseline: The baseline to persist.
    ///   - path: The destination file.
    /// - Throws: If the file can't be written.
    func write(_ baseline: Baseline, to path: URL) throws
}
