import Foundation
import BouncerCore

/// Builds a `Baseline` from a fresh analysis result, for `bouncer baseline update`.
enum BaselineBuilder {
    /// Fingerprints every finding that has a real line to hash, skipping file-level ones.
    ///
    /// - Parameters:
    ///   - result: The analysis result to accept into the baseline.
    ///   - repoRoot: The repository root, for relative-path fingerprints.
    /// - Returns: A baseline containing every fingerprintable finding.
    static func build(from result: AnalysisResult, repoRoot: URL) -> Baseline {
        var lineCache: [URL: [Substring]] = [:]
        let fingerprints = result.findings.compactMap {
            fingerprint(for: $0, repoRoot: repoRoot, lineCache: &lineCache)
        }
        return Baseline(fingerprints: Set(fingerprints))
    }

    /// Builds one finding's fingerprint by reading its offending line back from disk.
    ///
    /// - Parameters:
    ///   - finding: The finding to fingerprint.
    ///   - repoRoot: The repository root, for the relative path.
    ///   - lineCache: A per-file line cache, populated on demand.
    /// - Returns: The fingerprint, or `nil` if the finding's line is out of range.
    private static func fingerprint(
        for finding: Finding, repoRoot: URL, lineCache: inout [URL: [Substring]]
    ) -> FindingFingerprint? {
        let lines = cachedLines(of: finding.filePath, cache: &lineCache)
        guard finding.line >= 1, finding.line <= lines.count else { return nil }
        let relativePath = relativePath(of: finding.filePath, repoRoot: repoRoot)
        let lineContent = String(lines[finding.line - 1])
        return Baseline.fingerprint(ruleID: finding.ruleID, relativePath: relativePath, lineContent: lineContent)
    }

    /// Reads and caches a file's lines, so repeated findings in the same file don't re-read it.
    ///
    /// - Parameters:
    ///   - url: The file to read.
    ///   - cache: The per-file line cache.
    /// - Returns: The file's lines, or an empty array if it can't be read.
    private static func cachedLines(of url: URL, cache: inout [URL: [Substring]]) -> [Substring] {
        if let cached = cache[url] { return cached }
        let text = try? String(contentsOf: url, encoding: .utf8)
        let lines = text?.split(separator: "\n", omittingEmptySubsequences: false) ?? []
        cache[url] = lines
        return lines
    }

    /// Expresses a path relative to the repo root.
    ///
    /// - Parameters:
    ///   - url: The absolute path.
    ///   - repoRoot: The repository root.
    /// - Returns: The path relative to `repoRoot`, or the original path.
    private static func relativePath(of url: URL, repoRoot: URL) -> String {
        let root = repoRoot.path
        guard url.path.hasPrefix(root) else { return url.path }
        return String(url.path.dropFirst(root.count + 1))
    }
}
