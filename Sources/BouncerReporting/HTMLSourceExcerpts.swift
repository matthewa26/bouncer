import Foundation
import BouncerCore

/// The source code the HTML report embeds so each finding can show the code it's about: every file is read once,
/// the lines around its findings (and around their quick fixes) are merged into runs, so overlapping windows are
/// stored once, and each run is kept per file rather than per finding.
struct HTMLSourceExcerpts {
    /// How many lines the report shows above and below a finding's line, and around a quick fix.
    static let radius = 2
    /// The longest line the report embeds, in characters; a longer line is cut there and marked.
    static let maxLineLength = 240
    /// Ends a line that was cut at `maxLineLength`, so the page can mark it. It never occurs in source text.
    static let truncationMark = "\u{0}"
    /// Extensions of data and documentation files, compared lowercased, whose code the report doesn't embed: their
    /// findings (mostly duplicated blocks and long lines in generated data) teach little from a preview, and on
    /// large projects they made up most of the report's size. Their quick fixes are still embedded.
    static let skippedExtensions: Set<String> = [
        "json", "jsonc", "md", "markdown", "mdx", "lock", "po", "pot", "csv", "tsv", "txt", "rst"
    ]
    /// File names, compared lowercased, that keep their previews despite `skippedExtensions`: manifests, whose
    /// findings show something worth learning.
    static let previewedManifests: Set<String> = ["package.json", "composer.json"]

    /// Each file's runs of lines, in the order of the report's file table, or `nil` for a file that couldn't be
    /// read as UTF-8 or has no finding inside it.
    private(set) var code: [[HTMLReportData.Chunk]?]
    /// Each finding's quick fix, in the result's order, or `nil` where there's none.
    private(set) var fixes: [HTMLReportData.Fix?]

    /// Reads each file with findings once and collects the lines and fixes the report embeds.
    ///
    /// - Parameters:
    ///   - findings: The findings, in the result's order.
    ///   - fileIndices: Each finding's index into `files`.
    ///   - files: The report's files.
    ///   - lookups: How to read files and compute fixes.
    init(findings: [Finding], fileIndices: [Int], files: [URL], lookups: HTMLReportLookups) {
        code = Array(repeating: nil, count: files.count)
        fixes = Array(repeating: nil, count: findings.count)
        for (file, members) in Self.group(fileIndices, fileCount: files.count).enumerated() where !members.isEmpty {
            guard let text = lookups.readFile(files[file]) else { continue }
            let lines = text.components(separatedBy: "\n")
            let ranges = addFixes(lines, findings: members.map { ($0, findings[$0]) }, lookups: lookups)
            guard !ranges.isEmpty, Self.showsPreview(of: files[file]) else { continue }
            code[file] = Self.merged(ranges).map { Self.chunk(of: lines, covering: $0) }
        }
    }

    /// Works out one file's fixes, and the windows of lines its findings and fixes would show.
    ///
    /// - Parameters:
    ///   - lines: The file's lines, split on `\n`.
    ///   - findings: The file's findings, each with its index in the result.
    ///   - lookups: How to compute fixes.
    /// - Returns: The windows, unmerged, for a preview if the file gets one.
    private mutating func addFixes(_ lines: [String], findings: [(Int, Finding)],
                                   lookups: HTMLReportLookups) -> [ClosedRange<Int>] {
        let count = lines.last == "" ? lines.count - 1 : lines.count
        var ranges: [ClosedRange<Int>] = []
        for (index, finding) in findings {
            let fix = lookups.fix(finding, lines)
            fixes[index] = fix.map { HTMLReportData.Fix($0, display: Self.display) }
            let fixWindow = fix.flatMap { Self.window(of: $0, count: count) }
            ranges += [Self.window(around: finding.line, count: count), fixWindow].compactMap { $0 }
        }
        return ranges
    }

    /// Whether the report embeds a file's code: not for data and documentation files, except manifests.
    ///
    /// - Parameter file: The file.
    /// - Returns: `false` if its extension is in `skippedExtensions` and its name isn't in `previewedManifests`.
    static func showsPreview(of file: URL) -> Bool {
        previewedManifests.contains(file.lastPathComponent.lowercased())
            || !skippedExtensions.contains(file.pathExtension.lowercased())
    }

    /// Groups findings by file.
    ///
    /// - Parameters:
    ///   - fileIndices: Each finding's file index.
    ///   - fileCount: The number of files.
    /// - Returns: For each file, the indices of its findings.
    private static func group(_ fileIndices: [Int], fileCount: Int) -> [[Int]] {
        var members = [[Int]](repeating: [], count: fileCount)
        for (index, file) in fileIndices.enumerated() { members[file].append(index) }
        return members
    }

    /// The lines shown around a finding.
    ///
    /// - Parameters:
    ///   - line: The finding's 1-based line.
    ///   - count: The number of lines in the file.
    /// - Returns: The window, or `nil` if the line isn't in the file.
    static func window(around line: Int, count: Int) -> ClosedRange<Int>? {
        guard line >= 1, line <= count else { return nil }
        return max(1, line - radius)...min(count, line + radius)
    }

    /// The lines a quick fix replaces, with the context shown around them.
    ///
    /// - Parameters:
    ///   - fix: The fix.
    ///   - count: The number of lines in the file.
    /// - Returns: The window, or `nil` if none of it is in the file.
    static func window(of fix: QuickFix, count: Int) -> ClosedRange<Int>? {
        let last = fix.startLine + max(fix.removed.count, 1) - 1
        let (low, high) = (max(1, fix.startLine - radius), min(count, last + radius))
        return low <= high ? low...high : nil
    }

    /// Merges overlapping and adjacent windows, so no line is stored twice.
    ///
    /// - Parameter ranges: The windows, in any order.
    /// - Returns: The merged windows, in line order.
    static func merged(_ ranges: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
        ranges.sorted { $0.lowerBound < $1.lowerBound }.reduce(into: []) { merged, range in
            guard let last = merged.last, range.lowerBound <= last.upperBound + 1 else { return merged.append(range) }
            merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
        }
    }

    /// Cuts a window's lines out of a file.
    ///
    /// - Parameters:
    ///   - lines: The file's lines.
    ///   - range: The 1-based lines to keep.
    /// - Returns: The run, with each line prepared for display.
    private static func chunk(of lines: [String], covering range: ClosedRange<Int>) -> HTMLReportData.Chunk {
        HTMLReportData.Chunk(start: range.lowerBound, lines: lines[(range.lowerBound - 1)...(range.upperBound - 1)]
            .map(display))
    }

    /// Prepares a line for display: drops a Windows line ending, and cuts a line longer than `maxLineLength`,
    /// ending it with `truncationMark`.
    ///
    /// - Parameter line: The line as it is in the file.
    /// - Returns: The line to embed.
    static func display(_ line: String) -> String {
        let line = line.hasSuffix("\r") ? String(line.dropLast()) : line
        guard let cut = line.index(line.startIndex, offsetBy: maxLineLength, limitedBy: line.endIndex),
              cut < line.endIndex else { return line }
        return String(line[..<cut]) + truncationMark
    }
}
