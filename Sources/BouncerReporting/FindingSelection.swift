import Foundation
import BouncerCore

/// Which findings a report shows: filters by rule, path, and severity, then a page of what's left.
///
/// It's applied to the final findings, after analysis, the baseline, and suppressions, so a filtered or
/// paged report never changes what was analyzed. With no filter and no page it leaves a result as is,
/// order included, so reports without these flags stay byte-identical.
public struct FindingSelection: Sendable, Equatable {
    /// The rule IDs to keep, or none to keep every rule.
    public var rules: [String] = []
    /// Glob patterns, relative to the repository root, of the files to keep, or none to keep every file.
    public var paths: [String] = []
    /// The least severe finding to keep, or `nil` to keep every severity.
    public var minimumSeverity: Severity?
    /// How many findings to show, or `nil` for all of them.
    public var limit: Int?
    /// How many findings, in the stable order, to skip before the page starts.
    public var offset = 0

    /// Creates a selection that keeps everything.
    public init() {}

    /// Whether any filter or page is set, so the findings need sorting and cutting.
    public var isActive: Bool { isFiltered || limit != nil || offset > 0 }

    /// Whether any rule, path, or severity filter is set.
    private var isFiltered: Bool { !rules.isEmpty || !paths.isEmpty || minimumSeverity != nil }

    /// Filters a result, sorts what's left by file, line, and rule, and cuts the requested page from it.
    ///
    /// - Parameters:
    ///   - result: The analysis result.
    ///   - repoRoot: The repository root, which `paths` globs are relative to.
    /// - Returns: The matching findings, the page of them to show, and the counts a footer needs.
    public func apply(to result: AnalysisResult, repoRoot: URL) -> SelectedFindings {
        guard isActive else { return SelectedFindings(all: result) }
        let matching = Self.sorted(result.findings.filter(keeps(repoRoot: repoRoot)), repoRoot: repoRoot)
        let start = min(offset, matching.count)
        let end = limit.map { min(start + $0, matching.count) } ?? matching.count
        return SelectedFindings(
            matching: AnalysisResult(findings: matching, coverage: result.coverage),
            page: Array(matching[start..<end]), offset: start, totalCount: result.findings.count
        )
    }

    /// Builds the filter for the rule, severity, and path settings.
    ///
    /// - Parameter repoRoot: The repository root, which `paths` globs are relative to.
    /// - Returns: Whether to keep a finding.
    private func keeps(repoRoot: URL) -> (Finding) -> Bool {
        let rules = Set(rules)
        let pathMatcher = PathFilter(globs: paths, repoRoot: repoRoot)
        return { finding in
            (rules.isEmpty || rules.contains(finding.ruleID))
                && finding.severity >= (minimumSeverity ?? .info) && pathMatcher.keeps(finding.filePath)
        }
    }

    /// Sorts findings in the stable order pages are cut from: by relative path, then line, then rule, with the
    /// message breaking any tie so the same findings always page the same way.
    ///
    /// - Parameters:
    ///   - findings: The findings.
    ///   - repoRoot: The repository root the paths are relative to.
    /// - Returns: The sorted findings.
    public static func sorted(_ findings: [Finding], repoRoot: URL) -> [Finding] {
        // Each path is worked out once: doing it inside the comparator dominated sorting many findings.
        let keyed = findings.map { (finding: $0, path: RepoPath.relative($0.filePath, to: repoRoot)) }
        return keyed.sorted { lhs, rhs in
            let left = (lhs.path, lhs.finding.line, lhs.finding.ruleID, lhs.finding.message)
            return left < (rhs.path, rhs.finding.line, rhs.finding.ruleID, rhs.finding.message)
        }.map(\.finding)
    }
}

/// Matches files against `--path` globs, working out each file's answer once however many findings it has.
private final class PathFilter {
    /// The glob patterns, relative to the repository root.
    private let globs: [String]
    /// The repository root.
    private let repoRoot: URL
    /// Each file's answer so far, by its full path.
    private var answers: [String: Bool] = [:]

    /// Creates a filter.
    ///
    /// - Parameters:
    ///   - globs: The glob patterns, or none to keep every file.
    ///   - repoRoot: The repository root the patterns are relative to.
    init(globs: [String], repoRoot: URL) {
        self.globs = globs
        self.repoRoot = repoRoot
    }

    /// Whether a file matches any of the globs.
    ///
    /// - Parameter file: The file.
    /// - Returns: `true` when there are no globs, or one matches the file's path relative to the root.
    func keeps(_ file: URL) -> Bool {
        guard !globs.isEmpty else { return true }
        if let answer = answers[file.path] { return answer }
        let relative = RepoPath.relative(file, to: repoRoot)
        let answer = globs.contains { GlobMatcher.matches(path: relative, pattern: $0) }
        answers[file.path] = answer
        return answer
    }
}

/// What a `FindingSelection` picked: every matching finding, and the page of them to show.
public struct SelectedFindings: Sendable {
    /// Every finding that passed the filters, in the stable order; what the exit code and summary count.
    public let matching: AnalysisResult
    /// The page of `matching` to show.
    public let page: AnalysisResult
    /// Where the page starts in `matching`.
    public let offset: Int
    /// How many findings there were before filtering.
    public let totalCount: Int

    /// Records a selection.
    ///
    /// - Parameters:
    ///   - matching: Every finding that passed the filters.
    ///   - page: The findings to show.
    ///   - offset: Where the page starts in `matching`.
    ///   - totalCount: How many findings there were before filtering.
    public init(matching: AnalysisResult, page: [Finding], offset: Int, totalCount: Int) {
        self.matching = matching
        self.page = AnalysisResult(findings: page, coverage: matching.coverage)
        self.offset = offset
        self.totalCount = totalCount
    }

    /// Selects every finding of a result, unfiltered and unpaged.
    ///
    /// - Parameter result: The analysis result.
    public init(all result: AnalysisResult) {
        self.init(matching: result, page: result.findings, offset: 0, totalCount: result.findings.count)
    }

    /// Where the next page starts, or `nil` when this page reaches the end.
    public var nextOffset: Int? {
        let end = offset + page.findings.count
        return end < matching.findings.count && !page.findings.isEmpty ? end : nil
    }
}
