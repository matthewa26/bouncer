import Foundation
import BouncerCore
import BouncerGit

/// One project rule over the repository's commit history as well as its dependency graph.
public protocol HistoryRule: Sendable {
    var id: String { get }

    /// Reports whether the rule runs, so history is only read when some rule needs it.
    ///
    /// - Parameter context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: Whether the rule is enabled.
    func isEnabled(in context: AnalysisContext) -> Bool

    /// How many days of history the rule reads.
    ///
    /// - Parameter context: Repo-wide state, including this rule's `sinceDays` parameter.
    /// - Returns: The window's length in days.
    func days(in context: AnalysisContext) -> Int

    /// Finds this rule's problems.
    ///
    /// - Parameters:
    ///   - log: The commits read for every history rule; each rule narrows it to its own window.
    ///   - index: The project's dependency graph.
    ///   - targets: The repo-relative paths being checked; findings land in these.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: The findings.
    func evaluate(_ log: ChangeLog, index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding]
}

extension HistoryRule {
    /// History rules run unless turned off.
    ///
    /// - Parameter context: Repo-wide state.
    /// - Returns: Whether the rule's settings enable it.
    public func isEnabled(in context: AnalysisContext) -> Bool {
        context.settings(for: id).enabled
    }
}

/// Flags the files that change most often and are most complex: where bugs concentrate and where
/// simplifying pays off first.
///
/// A file's score is its commit count over the last `sinceDays` days times its total cyclomatic complexity
/// (summed over its functions). Files with at least `minCommits` commits and `minComplexity` complexity are
/// ranked by score and the top `top` are reported, each at its most complex function. To bound the cost, only
/// the `10 × top` most-changed candidates are measured. Generated files (those whose header says so) and files
/// matching `ignore` are skipped.
public struct HotspotRule: HistoryRule {
    public let id = "hotspot"
    /// How many of the most-changed files are measured for each hotspot reported.
    static let candidatesPerHotspot = 10
    private let measurer: FunctionMeasuring

    /// Creates the rule.
    ///
    /// - Parameter measurer: Measures each candidate file's functions.
    public init(measurer: FunctionMeasuring) {
        self.measurer = measurer
    }

    /// Reads `sinceDays`.
    ///
    /// - Parameter context: Repo-wide state.
    /// - Returns: The window's length, 180 days by default.
    public func days(in context: AnalysisContext) -> Int {
        context.settings(for: id).parameters.int("sinceDays", default: 180)
    }

    /// Ranks churned, complex files and reports the top ones.
    ///
    /// - Parameters:
    ///   - log: The commits read.
    ///   - index: Unused; hotspots don't depend on imports.
    ///   - targets: The paths being checked; only these are ranked.
    ///   - context: Repo-wide state, with `minCommits`, `minComplexity`, `top`, and `ignore`.
    /// - Returns: One finding per reported hotspot.
    public func evaluate(
        _ log: ChangeLog, index: ProjectIndex, targets: Set<String>, context: AnalysisContext
    ) -> [Finding] {
        let parameters = context.settings(for: id).parameters
        let minComplexity = parameters.int("minComplexity", default: 30), top = parameters.int("top", default: 5)
        let ranked = churned(log, targets: targets, context: context).prefix(top * Self.candidatesPerHotspot)
            .compactMap { measure($0.path, commits: $0.commits, context: context) }
            .filter { $0.complexity >= minComplexity }.sorted(by: Hotspot.ranksBefore)
        let reported = Array(ranked.prefix(top))
        return reported.enumerated().map { finding(for: $1, rank: $0 + 1, of: reported.count, context: context) }
    }

    /// Lists the checked, unignored code files with at least `minCommits` commits in the window, most
    /// changed first.
    ///
    /// - Parameters:
    ///   - log: The commits read.
    ///   - targets: The paths being checked.
    ///   - context: Repo-wide state, with `minCommits` and `ignore`.
    /// - Returns: Each candidate and its commit count, by count descending, then by path.
    private func churned(
        _ log: ChangeLog, targets: Set<String>, context: AnalysisContext
    ) -> [(path: String, commits: Int)] {
        let parameters = context.settings(for: id).parameters
        let ignore = parameters.stringList("ignore", default: [])
        let ignored = { (path: String) in ignore.contains { GlobMatcher.matches(path: path, pattern: $0) } }
        let counts = ChangeLog.commitsByPath(log.within(days: days(in: context))) {
            targets.contains($0) && SourceCode.isCode($0) && !ignored($0)
        }.mapValues(\.count).filter { $0.value >= parameters.int("minCommits", default: 5) }
        return counts.map { (path: $0.key, commits: $0.value) }.sorted { ($0.commits, $1.path) > ($1.commits, $0.path) }
    }

    /// Measures one candidate file.
    ///
    /// - Parameters:
    ///   - path: The repo-relative path.
    ///   - commits: How many commits touched it in the window.
    ///   - context: Repo-wide state, for the repo root.
    /// - Returns: The hotspot, or `nil` if the file can't be read or measured.
    private func measure(_ path: String, commits: Int, context: AnalysisContext) -> Hotspot? {
        let url = RepoPath.url(path, in: context.repoRoot)
        guard let contents = try? FileSystemContentsProvider().contents(of: url) else { return nil }
        let file = SourceFile(path: url, language: Language.from(fileExtension: url.pathExtension), contents: contents)
        guard !SourceCode.isGenerated(file), let functions = measurer.functions(in: file), !functions.isEmpty else {
            return nil
        }
        let worst = functions.max { $0.complexity < $1.complexity }
        return Hotspot(path: path, commits: commits, complexity: functions.map(\.complexity).reduce(0, +), worst: worst)
    }

    /// Builds one hotspot's finding, at its most complex function.
    ///
    /// - Parameters:
    ///   - spot: The hotspot.
    ///   - rank: Its 1-based rank.
    ///   - count: How many hotspots are reported.
    ///   - context: Repo-wide state.
    /// - Returns: The finding.
    private func finding(for spot: Hotspot, rank: Int, of count: Int, context: AnalysisContext) -> Finding {
        let worst = spot.worst.map { function in
            let label = function.name.map { "\"\($0)\"" } ?? "line \(function.line)"
            return "; most complex: \(label) (\(function.complexity))"
        } ?? ""
        let message = "Hotspot #\(rank) of \(count): \(spot.commits) commits in the last \(days(in: context)) days, "
            + "total complexity \(spot.complexity)\(worst). Code that changes often and is complex is where "
            + "bugs concentrate; simplify it first."
        return ProjectFinding.make(id, spot.path, spot.worst?.line ?? 1, message, context)
    }
}

/// A file's churn and complexity.
struct Hotspot {
    let path: String
    let commits: Int
    let complexity: Int
    let worst: FunctionMeasure?

    /// Churn times complexity.
    var score: Int { commits * complexity }

    /// Orders hotspots by score, highest first, then by path.
    ///
    /// - Parameters:
    ///   - lhs: One hotspot.
    ///   - rhs: Another.
    /// - Returns: Whether `lhs` ranks first.
    static func ranksBefore(_ lhs: Hotspot, _ rhs: Hotspot) -> Bool {
        (lhs.score, rhs.path) > (rhs.score, lhs.path)
    }
}
