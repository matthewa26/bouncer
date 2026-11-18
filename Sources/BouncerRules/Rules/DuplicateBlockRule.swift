import Foundation
import BouncerCore

/// Flags a block of lines that appears more than once in the same file.
///
/// Uses an exact-match sliding window over normalized (whitespace-trimmed)
/// lines - intra-file only, no cross-file comparison, and no tolerance for
/// near-duplicates. That's the deliberately cheap v1 approximation of clone
/// detection.
public struct DuplicateBlockRule: Rule {
    public static let ruleID = "duplicate-block"
    public let id = DuplicateBlockRule.ruleID

    /// Creates the rule. Duplication detection is language-agnostic, so no profile is needed.
    public init() {}

    /// Flags the second and later occurrences of any repeated block of lines.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's `windowSize` parameter.
    /// - Returns: One finding per repeated block occurrence.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        let windowSize = settings.parameters.int("windowSize", default: 6)
        guard settings.enabled, file.lines.count >= windowSize * 2 else { return [] }
        var seen: [String: Int] = [:]
        return (0...(file.lines.count - windowSize)).compactMap { start in
            finding(atWindowStart: start, size: windowSize, file: file, seen: &seen, severity: settings.severity)
        }
    }

    /// Checks one window position and records a finding if it repeats an earlier one.
    ///
    /// - Parameters:
    ///   - start: The window's starting line index.
    ///   - size: The window's length in lines.
    ///   - file: The file being scanned.
    ///   - seen: Previously seen window contents, keyed by normalized text.
    ///   - severity: The severity to report at.
    /// - Returns: A finding, or `nil` if this window hasn't been seen before.
    private func finding(
        atWindowStart start: Int, size: Int, file: SourceFile, seen: inout [String: Int], severity: Severity
    ) -> Finding? {
        let key = normalizedWindow(start: start, size: size, file: file)
        guard !key.isEmpty else { return nil }
        defer { seen[key] = seen[key] ?? start }
        guard let firstSeenAt = seen[key] else { return nil }
        let message = "Duplicates the \(size)-line block starting at line \(firstSeenAt + 1)."
        return Finding(ruleID: id, severity: severity, filePath: file.path, line: start + 1, message: message)
    }

    /// Builds a normalized key for a window of lines, for exact-match comparison.
    ///
    /// - Parameters:
    ///   - start: The window's starting line index.
    ///   - size: The window's length in lines.
    ///   - file: The file the window is drawn from.
    /// - Returns: The joined, trimmed lines, or `""` if the window is entirely blank.
    private func normalizedWindow(start: Int, size: Int, file: SourceFile) -> String {
        let lines = file.lines[start..<(start + size)].map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.allSatisfy(\.isEmpty) ? "" : lines.joined(separator: "\n")
    }
}
