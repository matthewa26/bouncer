import BouncerCore

/// Fixes for import findings: a repeated import line, and an unsorted block of one-line imports.
enum ImportFixes {
    /// The fixers, keyed by rule ID.
    static let fixers: [String: QuickFixes.Fixer] = [
        "duplicate-import": duplicateImport,
        "unsorted-imports": unsortedImports
    ]

    /// The earlier line a `duplicate-import` message names, `… is already imported on line 3; …`.
    private static let earlierLine = TextPattern(#"already imported on line (\d+)\b"#)

    /// Deletes a repeated import when it's a complete one-line statement identical to the import it repeats.
    ///
    /// An import that only shares the module, such as `import { b } from "x"` after `import { a } from "x"`, needs
    /// merging by hand, so it gets no fix.
    ///
    /// - Parameter site: The finding's site, the repeat.
    /// - Returns: The edit, or `nil` when the lines differ or the import spans several lines.
    @Sendable static func duplicateImport(_ site: FixSite) -> QuickFix? {
        guard let earlier = earlierLine.captures(in: site.finding.message).flatMap({ Int($0[1]) }),
              earlier >= 1, earlier <= site.lines.count, earlier != site.index + 1,
              site.lines[earlier - 1].trimmed == site.text.trimmed, isWholeStatement(site) else { return nil }
        return QuickFix(startLine: site.index + 1, removed: [site.text], added: [])
    }

    /// Sorts the block of one-line imports around the reported line, the way `unsorted-imports` orders them.
    ///
    /// - Parameter site: The finding's site, an out-of-order import.
    /// - Returns: The edit, or `nil` when the block isn't all one-line imports between blank or comment lines,
    ///   or is already sorted.
    @Sendable static func unsortedImports(_ site: FixSite) -> QuickFix? {
        let key = { (line: String) in ImportSortKey.key(for: line, language: site.language) }
        guard let range = importBlock(around: site, key: key) else { return nil }
        let block = Array(site.lines[range])
        let sorted = block.enumerated()
            .sorted { (key($0.element) ?? "", $0.offset) < (key($1.element) ?? "", $1.offset) }.map(\.element)
        guard sorted != block else { return nil }
        return QuickFix(startLine: range.lowerBound + 1, removed: block, added: sorted)
    }

    /// Finds the run of one-line imports around the reported line.
    ///
    /// - Parameters:
    ///   - site: The finding's site.
    ///   - key: The language's sort key, `nil` for a line that isn't a one-line import.
    /// - Returns: The run's line indices, or `nil` when the reported line isn't an import or the run doesn't sit
    ///   between blank lines, comments, or the file's edges.
    private static func importBlock(around site: FixSite, key: (String) -> String?) -> ClosedRange<Int>? {
        guard key(site.text) != nil else { return nil }
        let start = (0...site.index).reversed().prefix { key(site.lines[$0]) != nil }.last ?? site.index
        let end = (site.index..<site.lines.count).prefix { key(site.lines[$0]) != nil }.last ?? site.index
        guard isBoundary(site.lines, start - 1), isBoundary(site.lines, end + 1) else { return nil }
        return start...end
    }

    /// Checks that the reported line is one complete statement: no bracket left open, no continuation.
    ///
    /// - Parameter site: The finding's site.
    /// - Returns: Whether the line stands alone.
    private static func isWholeStatement(_ site: FixSite) -> Bool {
        guard let code = site.code?.masked.trimmed, let last = code.last, !"{(,\\".contains(last) else { return false }
        let opened = code.filter { "([{".contains($0) }.count
        return opened == code.filter { ")]}".contains($0) }.count
    }

    /// Checks whether a line can sit next to a sorted block: the file's edge, a blank line, or a comment.
    ///
    /// - Parameters:
    ///   - lines: The file's lines.
    ///   - index: The line's index, which may be just outside the file.
    /// - Returns: Whether the block can end there.
    private static func isBoundary(_ lines: [String], _ index: Int) -> Bool {
        guard lines.indices.contains(index) else { return true }
        let line = lines[index].trimmed
        return line.isEmpty || ["//", "#", "/*", "*"].contains { line.hasPrefix($0) }
    }
}

/// The sort keys `unsorted-imports` orders one-line imports by, per language.
enum ImportSortKey {
    /// A one-line Swift import, attributes and kind allowed: `@testable import struct Kit.Thing`.
    private static let swift = TextPattern(
        #"^(?:@\w+(?:\([^)]*\))?\s+)*import\s+"# + #"(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?"#
            + #"([\w.]+)\s*$"#
    )
    /// A one-line TypeScript or JavaScript import with a `from` clause.
    private static let script = TextPattern(#"^import\s+(?:type\s+)?[^'"]*?\bfrom\s*['"]([^'"]+)['"]\s*;?\s*$"#)
    /// A one-line Python `import a, b as c`.
    private static let pythonImport = TextPattern(
        #"^import\s+([\w.]+)(?:\s+as\s+\w+)?(?:\s*,\s*[\w.]+(?:\s+as\s+\w+)?)*\s*$"#
    )
    /// A one-line Python `from x import y`, without parentheses or a continuation.
    private static let pythonFrom = TextPattern(##"^from\s+([\w.]+)\s+import\s+[^()\\#]+$"##)

    /// The key a one-line import sorts by.
    ///
    /// - Parameters:
    ///   - line: The line.
    ///   - language: The file's language.
    /// - Returns: The key, or `nil` when the line isn't a one-line import the fixer can sort.
    static func key(for line: String, language: Language) -> String? {
        switch language {
        case .swift: swift.captures(in: line).map { $0[1].lowercased() }
        case .typescript, .javascript: script.captures(in: line).map { scriptKey($0[1]) }
        case .python: pythonKey(line)
        default: nil
        }
    }

    /// Ranks a TypeScript or JavaScript specifier's group (packages, then aliases, then `../`, then `./`) ahead of
    /// its name.
    ///
    /// - Parameter specifier: The module specifier.
    /// - Returns: The key.
    private static func scriptKey(_ specifier: String) -> String {
        let name = specifier.lowercased()
        return rank(of: name) + " " + name
    }

    /// Ranks a lowercased specifier's group as a sortable digit.
    ///
    /// - Parameter name: The lowercased specifier.
    /// - Returns: `1` for a package, `2` for an alias, `3` for a parent path, `4` for a sibling path.
    private static func rank(of name: String) -> String {
        if name.hasPrefix("../") { return "3" }
        if name.hasPrefix(".") { return "4" }
        return name.hasPrefix("@/") || name.hasPrefix("~") || name.hasPrefix("#") ? "2" : "1"
    }

    /// Keys a Python import isort's default way: `import x` lines, then `from x import y` lines, relative modules
    /// last in each, then by module.
    ///
    /// - Parameter line: The line.
    /// - Returns: The key, or `nil` for anything but a one-line import.
    private static func pythonKey(_ line: String) -> String? {
        guard let (style, module) = pythonImport.captures(in: line).map({ ("0", $0[1]) })
                ?? pythonFrom.captures(in: line).map({ ("1", $0[1]) }) else { return nil }
        return style + (module.hasPrefix(".") ? " 1 " : " 0 ") + module.lowercased()
    }
}
