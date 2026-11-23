import BouncerCore

/// The exact edit that fixes one finding in its file: lines to remove, starting at a line, and lines to put in
/// their place.
struct QuickFix: Sendable, Equatable {
    /// The 1-based line the edit starts at.
    let startLine: Int
    /// The lines the edit removes, starting at `startLine`, as they are in the file.
    let removed: [String]
    /// The lines that replace them.
    let added: [String]
}

/// Computes the exact fix for findings whose rule has a deterministic one, against the file as it is on disk.
///
/// Each rule's fixer reads the finding's line and its neighbours, and gives up (returns `nil`) whenever the code
/// doesn't have the exact shape the fix expects, since the file may have changed since the scan, or the fix would
/// need judgment.
enum QuickFixes {
    /// A rule's fixer: the edit for a finding at a site, or `nil` when there's no safe one.
    typealias Fixer = @Sendable (FixSite) -> QuickFix?

    /// Each fixable rule's fixer, keyed by rule ID.
    private static let fixers: [String: Fixer] = WhitespaceFixes.fixers
        .merging(ImportFixes.fixers) { first, _ in first }
        .merging(RewriteFixes.fixers) { first, _ in first }
        .merging(DebugOutputFixes.fixers) { first, _ in first }

    /// Works out a finding's fix.
    ///
    /// - Parameters:
    ///   - finding: The finding.
    ///   - lines: Its file's lines, as `SourceFile.lines(of:)` splits them.
    /// - Returns: The edit, or `nil` when the rule has no deterministic fix or the lines no longer match.
    static func fix(for finding: Finding, lines: [String]) -> QuickFix? {
        guard let fixer = fixers[finding.ruleID], let site = FixSite(finding: finding, lines: lines) else { return nil }
        return fixer(site)
    }

    /// Every rule ID with a fixer, sorted.
    static var fixableRuleIDs: [String] {
        fixers.keys.sorted()
    }
}
