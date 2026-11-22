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

    /// Flags each repeated region once: consecutive repeated windows that copy consecutive earlier windows
    /// merge into one finding, so a copied 20-line block is one finding, not one per line.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's `windowSize` parameter.
    /// - Returns: One finding per repeated region, at its first line.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        let windowSize = settings.parameters.int("windowSize", default: 6)
        guard settings.enabled, file.lines.count >= windowSize * 2 else { return [] }
        return regions(repeatedWindows(size: windowSize, file: file)).map { region in
            finding(for: region, size: windowSize, file: file, severity: settings.severity)
        }
    }

    /// A run of repeated windows: where the copy starts, where the original starts, and how many windows long.
    private struct Region {
        let start: Int
        let source: Int
        var windows = 1
    }

    /// Lists every window that repeats an earlier one, with where it first appeared.
    ///
    /// - Parameters:
    ///   - size: The window's length in lines.
    ///   - file: The file being scanned.
    /// - Returns: `(start, source)` line indexes, in file order.
    private func repeatedWindows(size: Int, file: SourceFile) -> [(start: Int, source: Int)] {
        var seen: [String: Int] = [:]
        return (0...(file.lines.count - size)).compactMap { start in
            let key = normalizedWindow(start: start, size: size, file: file)
            guard !key.isEmpty else { return nil }
            defer { seen[key] = seen[key] ?? start }
            return seen[key].map { (start, $0) }
        }
    }

    /// Merges repeated windows into regions where both the copy and the original advance one line at a time.
    ///
    /// - Parameter windows: The repeated windows, in file order.
    /// - Returns: The merged regions.
    private func regions(_ windows: [(start: Int, source: Int)]) -> [Region] {
        windows.reduce(into: []) { regions, window in
            if let last = regions.last, window.start == last.start + last.windows,
               window.source == last.source + last.windows {
                regions[regions.count - 1].windows += 1
            } else {
                regions.append(Region(start: window.start, source: window.source))
            }
        }
    }

    /// Reports one repeated region.
    ///
    /// - Parameters:
    ///   - region: The region.
    ///   - size: The window's length in lines.
    ///   - file: The file being scanned.
    ///   - severity: The severity to report at.
    /// - Returns: A finding at the region's first line, naming both line ranges.
    private func finding(for region: Region, size: Int, file: SourceFile, severity: Severity) -> Finding {
        let length = region.windows + size - 1
        let message = "Lines \(region.start + 1)-\(region.start + length) duplicate lines "
            + "\(region.source + 1)-\(region.source + length)."
        return Finding(ruleID: id, severity: severity, filePath: file.path, line: region.start + 1, message: message)
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
