/// Fixes for whitespace findings: trailing whitespace and runs of blank lines.
enum WhitespaceFixes {
    /// The fixers, keyed by rule ID.
    static let fixers: [String: QuickFixes.Fixer] = [
        "trailing-whitespace": trailingWhitespace,
        "consecutive-blank-lines": consecutiveBlankLines
    ]

    /// The limit in a `consecutive-blank-lines` message, `More than 2 consecutive blank lines.`
    private static let blankLineLimit = TextPattern(#"^More than (\d+) consecutive blank lines"#)

    /// Strips the spaces and tabs ending the reported line.
    ///
    /// - Parameter site: The finding's site.
    /// - Returns: The edit, or `nil` when the line doesn't end in a space or tab.
    @Sendable static func trailingWhitespace(_ site: FixSite) -> QuickFix? {
        let text = site.text
        guard let last = text.last, last == " " || last == "\t" else { return nil }
        let kept = text.reversed().drop { $0 == " " || $0 == "\t" }
        return site.replacingLine(with: String(kept.reversed()))
    }

    /// Deletes the blank lines past the limit from the run of blank lines that starts on the reported line.
    ///
    /// - Parameter site: The finding's site, the run's first line.
    /// - Returns: The edit, or `nil` when the line doesn't start a run longer than the message's limit.
    @Sendable static func consecutiveBlankLines(_ site: FixSite) -> QuickFix? {
        guard let limit = blankLineLimit.captures(in: site.finding.message).flatMap({ Int($0[1]) }),
              isBlank(site.text), site.index == 0 || !isBlank(site.lines[site.index - 1]) else { return nil }
        let run = site.lines[site.index...].prefix(while: isBlank).count
        guard run > limit else { return nil }
        let extra = Array(site.lines[(site.index + limit)..<(site.index + run)])
        return QuickFix(startLine: site.index + limit + 1, removed: extra, added: [])
    }

    /// Checks whether a line is blank, as `consecutive-blank-lines` counts it: empty or only whitespace.
    ///
    /// - Parameter line: The line.
    /// - Returns: Whether it's blank.
    private static func isBlank(_ line: String) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }
}
