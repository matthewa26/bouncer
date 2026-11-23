import Foundation
import BouncerCore

/// Renders the cluster `next_batch` picked: a header naming it, each finding with the code around it, and the
/// `verify` call to make after fixing them, all within a character budget.
///
/// Findings are shown in whole blocks (a finding, or findings whose code overlaps, and that code), so the text
/// never ends on a partial line. When the cluster doesn't fit, it ends with how many findings are left in it and
/// the `findings` call that lists them.
public struct NextBatchWriter: Sendable {
    /// The longest code line shown before it's cut.
    static let maxCodeLineChars = 160
    /// What a finding line starts with.
    private static let findingIndent = "  "
    /// What a code line starts with, before its number.
    private static let codeIndent = "    "
    /// The line that stands for skipped code between two shown lines.
    private static let gap = codeIndent + "..."

    /// The most characters the text may take.
    private let maxChars: Int

    /// Creates a writer.
    ///
    /// - Parameter maxChars: The most characters the text may take.
    public init(maxChars: Int) {
        self.maxChars = maxChars
    }

    /// Renders a pick. When the budget is too small for even one finding with the footer, the footer gives way.
    ///
    /// - Parameters:
    ///   - pick: The cluster and how many others are left.
    ///   - source: The file's lines as they are now.
    /// - Returns: The text.
    public func render(_ pick: NextBatchPick, source: NextBatchSource) -> String {
        let cluster = pick.cluster
        let (header, footer) = (Self.header(pick, source: source), Self.footer(cluster))
        let room = maxChars - header.count - 1
        var (body, cut) = self.body(cluster, source: source, room: room - footer.count - 1)
        var tail = [footer]
        let bare = cut == cluster.findings.count ? self.body(cluster, source: source, room: room) : nil
        if let bare, bare.cut < cut { ((body, cut), tail) = (bare, []) }
        let more = cut > 0 ? [Self.moreLine(cluster, remaining: cut)] : []
        return ([header] + body + more + tail).joined(separator: "\n")
    }

    /// The blocks that fit, leaving room for the line about cut findings when some don't.
    ///
    /// - Parameters:
    ///   - cluster: The cluster.
    ///   - source: The file's lines.
    ///   - room: The most characters the body may take, a newline after each line.
    /// - Returns: The body's lines, and how many findings were cut.
    private func body(_ cluster: FindingCluster, source: NextBatchSource, room: Int) -> ([String], cut: Int) {
        let blocks = NextBatchSnippets.blocks(cluster, lines: source.lines)
        let rendered = Self.rendered(blocks, source: source)
        let whole = Self.fitting(rendered, blocks: blocks, room: room)
        guard whole.shown < cluster.findings.count else { return (whole.lines, 0) }
        let reserve = Self.moreLine(cluster, remaining: cluster.findings.count).count + 1
        let cut = Self.fitting(rendered, blocks: blocks, room: room - reserve)
        return (cut.lines, cluster.findings.count - cut.shown)
    }

    /// Keeps the leading blocks that fit.
    ///
    /// - Parameters:
    ///   - rendered: Each block's lines.
    ///   - blocks: The blocks, for how many findings each shows.
    ///   - room: The most characters the kept lines may take, a newline after each.
    /// - Returns: The kept lines, and how many findings they show.
    private static func fitting(
        _ rendered: [[String]], blocks: [SnippetBlock], room: Int
    ) -> (lines: [String], shown: Int) {
        var (kept, used, shown) = ([String](), 0, 0)
        for (lines, block) in zip(rendered, blocks) {
            used += lines.reduce(0) { $0 + $1.count + 1 }
            if used > room { break }
            (kept, shown) = (kept + lines, shown + block.findings.count)
        }
        return (kept, shown)
    }

    /// Renders every block, leaving out a message that repeats the one before, as `--format agent` does.
    ///
    /// - Parameters:
    ///   - blocks: The blocks.
    ///   - source: The file's lines.
    /// - Returns: Each block's lines.
    private static func rendered(_ blocks: [SnippetBlock], source: NextBatchSource) -> [[String]] {
        var lastMessage: String?
        return blocks.map { block in
            let findings = block.findings.map { finding in
                let message = finding.message.replacingOccurrences(of: "\n", with: " ")
                defer { lastMessage = message }
                return findingIndent + (message == lastMessage ? "\(finding.line)" : "\(finding.line) \(message)")
            }
            return findings + (source.lines.map { code(block.lines, in: $0) } ?? [])
        }
    }

    /// The line that names the cluster.
    ///
    /// - Parameters:
    ///   - pick: The cluster and how many others are left.
    ///   - source: The file's lines, for whether they're shown.
    /// - Returns: A line such as
    ///   `Sources/A.swift · force-unwrap (mechanical, warning) · 4 findings · 37 clusters left`.
    static func header(_ pick: NextBatchPick, source: NextBatchSource) -> String {
        let cluster = pick.cluster
        let count = cluster.findings.count == 1 ? "1 finding" : "\(cluster.findings.count) findings"
        let left = pick.clustersLeft == 1 ? "1 cluster left" : "\(pick.clustersLeft) clusters left"
        let text = "\(cluster.path) · \(cluster.ruleID) (\(cluster.cost.rawValue), \(cluster.severity.rawValue))"
        return "\(text) · \(count) · \(left)" + note(source)
    }

    /// Says why no code is shown, when none is.
    ///
    /// - Parameter source: The file's lines.
    /// - Returns: The note, or nothing when the code is shown.
    private static func note(_ source: NextBatchSource) -> String {
        if source.changedSinceScan { return " (changed since scan; verify it)" }
        return source.lines == nil ? " (can't read the file)" : ""
    }

    /// The line saying how many findings were cut and how to list them.
    ///
    /// - Parameters:
    ///   - cluster: The cluster.
    ///   - remaining: How many findings were cut.
    /// - Returns: The line.
    static func moreLine(_ cluster: FindingCluster, remaining: Int) -> String {
        "+\(remaining) more in this cluster: call findings with rule \(cluster.ruleID) and path \(cluster.path)."
    }

    /// The line that says what to do after the fix.
    ///
    /// - Parameter cluster: The cluster.
    /// - Returns: The line.
    static func footer(_ cluster: FindingCluster) -> String {
        "Next: fix these, then call verify with files [\"\(cluster.path)\"]; then next_batch again."
    }

    /// Renders code lines with their numbers, marking skipped stretches.
    ///
    /// - Parameters:
    ///   - numbers: The 1-based line numbers, ascending.
    ///   - lines: The file's lines.
    /// - Returns: The rendered lines.
    private static func code(_ numbers: [Int], in lines: [String]) -> [String] {
        var rendered: [String] = []
        for (index, number) in numbers.enumerated() {
            if index > 0, numbers[index - 1] + 1 < number { rendered.append(gap) }
            let text = clipped(lines[number - 1])
            rendered.append(codeIndent + "\(number)|" + (text.isEmpty ? "" : " " + text))
        }
        return rendered
    }

    /// Cuts a long code line and drops its trailing whitespace.
    ///
    /// - Parameter line: The line.
    /// - Returns: The line, at most `maxCodeLineChars` long plus an ellipsis.
    private static func clipped(_ line: String) -> String {
        var text = line
        while let last = text.last, last.isWhitespace { text.removeLast() }
        return text.count > maxCodeLineChars ? text.prefix(maxCodeLineChars) + "…" : text
    }
}
