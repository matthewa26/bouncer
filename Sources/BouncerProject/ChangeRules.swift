import Foundation
import BouncerCore
import BouncerGit

/// `check`'s change rules: `oversized-change` over the staged diff, and `complexity-ratchet` and
/// `public-api-growth` against the base branch. Each does nothing outside a git repository.
public struct ChangeRules: ChangeAnalyzer {
    private let source: ChangeSource
    private let oversized: OversizedChangeRule?
    private let ratchet: ComplexityRatchetRule
    private let apiGrowth: PublicAPIGrowthRule?

    /// Creates the change rules.
    ///
    /// - Parameters:
    ///   - source: Reads the staged diff and base-branch file versions.
    ///   - measurer: Measures functions for `complexity-ratchet`, and parses module facts for
    ///     `public-api-growth` if it can.
    ///   - checksStagedDiff: Whether the files checked are the staged ones, so `oversized-change` applies.
    ///   - exclude: The config's `exclude` globs, left out of the staged diff's size.
    public init(source: ChangeSource, measurer: FunctionMeasuring, checksStagedDiff: Bool, exclude: [String] = []) {
        self.source = source
        oversized = checksStagedDiff ? OversizedChangeRule(exclude: exclude) : nil
        ratchet = ComplexityRatchetRule(measurer: measurer)
        apiGrowth = (measurer as? ModuleFactsParsing).map(PublicAPIGrowthRule.init)
    }

    /// Runs each enabled change rule.
    ///
    /// - Parameters:
    ///   - files: The files being checked.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The combined findings.
    public func findings(for files: [SourceFile], context: AnalysisContext) -> [Finding] {
        let size = oversizedFinding(files, context: context).map { [$0] } ?? []
        let growth = apiGrowth?.evaluate(files, source: source, context: context) ?? []
        guard context.settings(for: ratchet.id).enabled else { return size + growth }
        return size + ratchet.evaluate(files, source: source, context: context) + growth
    }

    /// Runs `oversized-change` over the staged diff, when it applies and is enabled.
    ///
    /// - Parameters:
    ///   - files: The files being checked.
    ///   - context: Repo-wide state.
    /// - Returns: The finding, or `nil`.
    private func oversizedFinding(_ files: [SourceFile], context: AnalysisContext) -> Finding? {
        guard let oversized, context.settings(for: oversized.id).enabled,
              let changes = source.stagedChanges(in: context.repoRoot) else { return nil }
        let targets = Set(files.map { RepoPath.relative($0.path, to: context.repoRoot) })
        return oversized.evaluate(changes, targets: targets, context: context)
    }
}

/// Flags a staged change too big to review well, as one finding at its largest changed file.
///
/// Counts added plus deleted lines across the staged diff, leaving out lockfiles, snapshots, the config's
/// `exclude` globs, and anything in `ignore`; pure renames count 0. Reports when the total exceeds
/// `maxChangedLines` or the file count exceeds `maxFiles`.
public struct OversizedChangeRule: Sendable {
    public let id = "oversized-change"
    static let defaultIgnore = Lockfiles.names.sorted().map { "**/" + $0 } + ["**/*.snap"]
    private let exclude: [String]

    /// Creates the rule.
    ///
    /// - Parameter exclude: The config's `exclude` globs.
    public init(exclude: [String] = []) {
        self.exclude = exclude
    }

    /// Measures the staged diff and reports it if it's over either limit.
    ///
    /// - Parameters:
    ///   - changes: The staged changes.
    ///   - targets: The paths being checked; the finding lands in the largest of these when there is one.
    ///   - context: Repo-wide state, with `maxChangedLines`, `maxFiles`, and `ignore`.
    /// - Returns: The finding, or `nil` within the limits.
    public func evaluate(_ changes: [GitFileChange], targets: Set<String>, context: AnalysisContext) -> Finding? {
        let parameters = context.settings(for: id).parameters
        let counted = countedChanges(changes, ignoring: parameters.stringList("ignore", default: []))
        let lines = counted.map(\.changedLines).reduce(0, +)
        let maxLines = parameters.int("maxChangedLines", default: 400)
        let maxFiles = parameters.int("maxFiles", default: 30)
        guard lines > maxLines || counted.count > maxFiles,
              let location = Self.largest(of: counted, preferring: targets) else { return nil }
        let size = "The staged change is \(lines) lines in \(counted.count) file\(counted.count == 1 ? "" : "s"), "
        return ProjectFinding.make(id, location.path, 1, size + Self.advice(maxLines, maxFiles), context)
    }

    /// Words the limits and what to do about exceeding them.
    ///
    /// - Parameters:
    ///   - maxLines: The line limit.
    ///   - maxFiles: The file limit.
    /// - Returns: The end of the finding's message.
    private static func advice(_ maxLines: Int, _ maxFiles: Int) -> String {
        "over the \(maxLines)-line or \(maxFiles)-file limit; split it into smaller commits that can each be "
            + "reviewed properly."
    }

    /// Leaves out lockfiles, snapshots, excluded files, and the `ignore` globs.
    ///
    /// - Parameters:
    ///   - changes: The staged changes.
    ///   - ignore: The rule's own `ignore` globs.
    /// - Returns: The changes that count toward the size.
    private func countedChanges(_ changes: [GitFileChange], ignoring ignore: [String]) -> [GitFileChange] {
        let globs = Self.defaultIgnore + exclude + ignore
        return changes.filter { change in !globs.contains { GlobMatcher.matches(path: change.path, pattern: $0) } }
    }

    /// Picks where to report: the largest change in a checked file, else the largest change.
    ///
    /// - Parameters:
    ///   - changes: The counted changes.
    ///   - targets: The paths being checked.
    /// - Returns: The change, or `nil` if there are none.
    private static func largest(of changes: [GitFileChange], preferring targets: Set<String>) -> GitFileChange? {
        let sorted = changes.sorted { ($0.changedLines, $1.path) > ($1.changedLines, $0.path) }
        return sorted.first { targets.contains($0.path) } ?? sorted.first
    }
}
