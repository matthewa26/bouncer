import Foundation
import BouncerCore

/// How re-analyzing some files changed their findings: which were fixed, which are still there, and which are new.
///
/// A finding is still there when the new run has one from the same rule in the same file with the same message,
/// whatever its line, since an edit above it moves it; failing that, one from the same rule on the same line, since
/// a message can quote a number the edit changed. Each old finding matches at most one new one.
public struct FindingDelta: Sendable, Equatable {
    /// The old findings with no match in the new run.
    public let fixed: [Finding]
    /// The new run's findings that match an old one, as the new run reports them.
    public let remaining: [Finding]
    /// The new run's findings that match no old one.
    public let new: [Finding]

    /// Compares the findings in some files before and after re-analyzing them.
    ///
    /// - Parameters:
    ///   - before: The files' findings before.
    ///   - after: The files' findings after.
    public init(before: [Finding], after: [Finding]) {
        var unmatched = before
        let byMessage = Self.match(after, against: &unmatched, same: Self.sameMessage)
        let byLine = Self.match(byMessage.unmatched, against: &unmatched, same: Self.sameLine)
        fixed = unmatched
        remaining = byMessage.matched + byLine.matched
        new = byLine.unmatched
    }

    /// Pairs each candidate with the first old finding it matches, removing that old finding.
    ///
    /// - Parameters:
    ///   - candidates: The new findings to match.
    ///   - old: The old findings still unmatched; matched ones are removed.
    ///   - same: Whether a new finding matches an old one.
    /// - Returns: The candidates that matched and those that didn't, each in order.
    private static func match(
        _ candidates: [Finding], against old: inout [Finding], same: (Finding, Finding) -> Bool
    ) -> (matched: [Finding], unmatched: [Finding]) {
        var matched: [Finding] = [], unmatched: [Finding] = []
        for candidate in candidates {
            if let index = old.firstIndex(where: { same(candidate, $0) }) {
                old.remove(at: index)
                matched.append(candidate)
            } else { unmatched.append(candidate) }
        }
        return (matched, unmatched)
    }

    /// Whether two findings are from the same rule in the same file with the same message.
    ///
    /// - Parameters:
    ///   - lhs: One finding.
    ///   - rhs: The other.
    /// - Returns: Whether they match.
    private static func sameMessage(_ lhs: Finding, _ rhs: Finding) -> Bool {
        lhs.ruleID == rhs.ruleID && lhs.message == rhs.message && lhs.filePath.path == rhs.filePath.path
    }

    /// Whether two findings are from the same rule on the same line of the same file.
    ///
    /// - Parameters:
    ///   - lhs: One finding.
    ///   - rhs: The other.
    /// - Returns: Whether they match.
    private static func sameLine(_ lhs: Finding, _ rhs: Finding) -> Bool {
        lhs.ruleID == rhs.ruleID && lhs.line == rhs.line && lhs.filePath.path == rhs.filePath.path
    }

    /// The counts, as one line: `3 fixed, 5 still there, 1 new.`
    public var summary: String {
        "\(fixed.count) fixed, \(remaining.count) still there, \(new.count) new."
    }
}
