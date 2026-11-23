import Foundation
import BouncerCore

/// A file's lines as they are now, for the code `next_batch` shows around each finding.
public struct NextBatchSource: Sendable, Equatable {
    /// The file's lines, or `nil` when it can't be read.
    public let lines: [String]?
    /// Whether the file changed on disk since the scan, so its lines may not match the findings.
    public let changedSinceScan: Bool

    /// Wraps a file's lines.
    ///
    /// - Parameters:
    ///   - lines: The file's lines, or `nil` when it can't be read.
    ///   - changedSinceScan: Whether it changed since the scan.
    public init(lines: [String]?, changedSinceScan: Bool = false) {
        (self.lines, self.changedSinceScan) = (lines, changedSinceScan)
    }

    /// Reads a file's lines.
    ///
    /// - Parameter url: The file.
    /// - Returns: The source, without lines when the file can't be read as UTF-8.
    public static func read(_ url: URL) -> NextBatchSource {
        NextBatchSource(lines: (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: "\n"))
    }
}

/// Some of a cluster's findings and the code lines shown under them, which overlap or touch.
struct SnippetBlock: Sendable, Equatable {
    /// The findings, by line.
    var findings: [Finding]
    /// The 1-based line numbers to show, ascending.
    var lines: [Int]
}

/// Works out which code lines to show for a cluster: a window around each finding of a mechanical rule, or the
/// enclosing declaration's line and the finding's line for a refactor, with blocks merged where they touch.
enum NextBatchSnippets {
    /// How many lines above and below a finding a window shows.
    static let contextRadius = 1

    /// A line that opens a declaration in most languages Bouncer reads: modifiers and attributes, then a keyword
    /// such as `func`, `def`, `fn`, `class`, or `struct`; or an Objective-C method.
    private static let declaration = try? NSRegularExpression(pattern: [
        #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"#,
        #"(?:(?:public|private|fileprivate|internal|open|static|class|final|override|mutating|nonmutating|"#,
        #"convenience|required|async|export|default|pub(?:\([^)]*\))?|unsafe|abstract|protected|virtual)\s+)*"#,
        #"(?:func|init|deinit|subscript|def|fn|function|class|struct|enum|protocol|extension|actor|impl|trait|"#,
        #"interface)\b|^[-+]\s*\("#
    ].joined())

    /// Splits a cluster's findings into blocks.
    ///
    /// - Parameters:
    ///   - cluster: The cluster.
    ///   - lines: The file's lines, or `nil` to show no code.
    /// - Returns: The blocks, in line order.
    static func blocks(_ cluster: FindingCluster, lines: [String]?) -> [SnippetBlock] {
        var blocks: [SnippetBlock] = []
        for finding in cluster.findings {
            let shown = lines.map { shownLines(finding.line, cost: cluster.cost, in: $0) } ?? []
            if let last = blocks.last, touches(last.lines, shown) {
                blocks[blocks.count - 1].findings.append(finding)
                blocks[blocks.count - 1].lines = Array(Set(last.lines + shown)).sorted()
            } else { blocks.append(SnippetBlock(findings: [finding], lines: shown)) }
        }
        return blocks
    }

    /// Whether a finding's lines overlap or follow straight on from a block's.
    ///
    /// - Parameters:
    ///   - block: The block's lines, ascending.
    ///   - shown: The finding's lines.
    /// - Returns: Whether they merge.
    private static func touches(_ block: [Int], _ shown: [Int]) -> Bool {
        guard let end = block.last, let start = shown.min() else { return false }
        return start <= end + 1
    }

    /// The lines to show for one finding.
    ///
    /// - Parameters:
    ///   - line: The finding's line.
    ///   - cost: Its rule's fix cost.
    ///   - lines: The file's lines.
    /// - Returns: The 1-based line numbers, ascending, within the file.
    static func shownLines(_ line: Int, cost: FixCost, in lines: [String]) -> [Int] {
        guard line >= 1, line <= lines.count else { return [] }
        guard cost == .refactor else {
            return Array(max(1, line - contextRadius)...min(lines.count, line + contextRadius))
        }
        return Array(Set([signatureLine(above: line, in: lines), line].compactMap { $0 })).sorted()
    }

    /// The nearest line at or above a line that opens a declaration.
    ///
    /// - Parameters:
    ///   - line: The 1-based line to search up from.
    ///   - lines: The file's lines.
    /// - Returns: The declaration's 1-based line, or `nil` when none is found.
    static func signatureLine(above line: Int, in lines: [String]) -> Int? {
        guard let declaration else { return nil }
        return (1...line).reversed().first { number in
            let text = lines[number - 1]
            return declaration.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
    }
}
