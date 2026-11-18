import Foundation
import BouncerCore

/// A block of lines starting at a matched line and ending where indentation returns to base.
public struct LineBlock: Sendable {
    /// The 0-indexed line the block's opening pattern matched.
    public let startLine: Int
    /// The 0-indexed last line still considered part of the block's body.
    public let endLine: Int
}

/// Finds indentation-delimited blocks, such as function bodies or switch statements.
///
/// This is a heuristic, not a parser: a block starts at a line matching a
/// given pattern and ends at the first later line whose indentation returns
/// to or below the starting line's indentation. It's what lets one generic
/// mechanism back `long-function`, `cyclomatic-complexity`,
/// `missing-documentation`, and `switch-on-type-smell` across every
/// heuristically-analyzed language.
public enum BlockSegmenter {
    /// Finds every block whose opening line matches `startPattern`.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - startPattern: A regular expression matching a block's opening line.
    /// - Returns: Every matched block, in file order.
    public static func blocks(in file: SourceFile, startPattern: String) -> [LineBlock] {
        guard let regex = try? NSRegularExpression(pattern: startPattern) else { return [] }
        var blocks: [LineBlock] = []
        var index = 0
        while index < file.lines.count {
            index = appendBlockIfMatching(at: index, in: file, regex: regex, into: &blocks)
        }
        return blocks
    }

    /// Checks one line for a match and, if found, appends its block and returns the next index to scan.
    ///
    /// - Parameters:
    ///   - index: The line to check.
    ///   - file: The file being scanned.
    ///   - regex: The compiled start pattern.
    ///   - blocks: The accumulated blocks, appended to on a match.
    /// - Returns: The index to resume scanning from.
    private static func appendBlockIfMatching(
        at index: Int, in file: SourceFile, regex: NSRegularExpression, into blocks: inout [LineBlock]
    ) -> Int {
        guard matches(regex, file.lines[index]) else { return index + 1 }
        let end = endOfBlock(startingAt: index, in: file)
        blocks.append(LineBlock(startLine: index, endLine: end))
        return end + 1
    }

    /// Finds where a block starting at `start` ends, by indentation return-to-base.
    ///
    /// - Parameters:
    ///   - start: The block's opening line index.
    ///   - file: The file being scanned.
    /// - Returns: The last line index still inside the block.
    private static func endOfBlock(startingAt start: Int, in file: SourceFile) -> Int {
        let baseIndent = Indentation.depth(of: file.lines[start])
        var end = start
        for index in (start + 1)..<file.lines.count {
            let line = file.lines[index]
            if LineClassifier.isBlank(line) { end = index; continue }
            if Indentation.depth(of: line) <= baseIndent { break }
            end = index
        }
        return end
    }

    /// Tests whether a line matches a compiled pattern.
    ///
    /// - Parameters:
    ///   - regex: The pattern to test.
    ///   - line: The line to test against.
    /// - Returns: Whether the pattern matches anywhere in the line.
    private static func matches(_ regex: NSRegularExpression, _ line: Substring) -> Bool {
        let text = String(line)
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
