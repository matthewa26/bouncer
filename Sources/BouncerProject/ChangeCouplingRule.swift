import Foundation
import BouncerCore
import BouncerGit

/// Flags two files that keep changing in the same commits although neither imports the other: a hidden
/// dependency, such as duplicated logic or a shared format, that the code doesn't show.
///
/// Over the last `sinceDays` days, a pair is reported when it shares at least `minShared` commits and its
/// coupling, shared commits over the average of the two files' commit counts, is at least `minRatio`.
/// Commits touching more than `maxFilesPerCommit` files (mass renames, reformatting) are ignored. Only files
/// in the dependency graph are paired, and pairs in the same node (one Swift target or Go package) or
/// joined by an import in either direction are skipped, since that coupling is visible.
public struct ChangeCouplingRule: HistoryRule {
    public let id = "change-coupling"

    /// Creates the rule.
    public init() {}

    /// Reads `sinceDays`.
    ///
    /// - Parameter context: Repo-wide state.
    /// - Returns: The window's length, 180 days by default.
    public func days(in context: AnalysisContext) -> Int {
        context.settings(for: id).parameters.int("sinceDays", default: 180)
    }

    /// Finds co-changing pairs with no import between them and reports each once.
    ///
    /// - Parameters:
    ///   - log: The commits read.
    ///   - index: The project's dependency graph, for which pairs are already related.
    ///   - targets: The paths being checked; a pair is reported in one of these.
    ///   - context: Repo-wide state, with `minShared`, `minRatio`, and `maxFilesPerCommit`.
    /// - Returns: One finding per hidden coupling.
    public func evaluate(
        _ log: ChangeLog, index: ProjectIndex, targets: Set<String>, context: AnalysisContext
    ) -> [Finding] {
        let maxFiles = context.settings(for: id).parameters.int("maxFilesPerCommit", default: 30)
        let commits = log.within(days: days(in: context)).filter { $0.changes.count <= maxFiles }
            .map { Set($0.changes.map(\.path)).filter { index.nodeOfFile[$0] != nil } }
        let counts = CoChangeCounts(commits: commits)
        return hiddenPairs(counts, related: Relatedness(index: index), context: context)
            .compactMap { finding(for: $0, counts: counts, targets: targets, context) }
    }

    /// Lists the pairs coupled strongly enough, without an import between them, in path order.
    ///
    /// - Parameters:
    ///   - counts: The commit counts.
    ///   - related: Which pairs the dependency graph already connects.
    ///   - context: Repo-wide state, with `minShared` and `minRatio`.
    /// - Returns: The pairs.
    private func hiddenPairs(_ counts: CoChangeCounts, related: Relatedness, context: AnalysisContext) -> [FilePair] {
        let parameters = context.settings(for: id).parameters
        let minShared = parameters.int("minShared", default: 5), minRatio = parameters.double("minRatio", default: 0.5)
        return counts.pairs.filter { pair, shared in
            shared >= minShared && counts.coupling(pair) >= minRatio && !related.connects(pair.first, pair.second)
        }.keys.sorted()
    }

    /// Builds a pair's finding in whichever of its files is being checked, preferring the first by path.
    ///
    /// - Parameters:
    ///   - pair: The two files.
    ///   - counts: Their commit counts.
    ///   - targets: The paths being checked.
    ///   - context: Repo-wide state.
    /// - Returns: The finding, or `nil` if neither file is being checked.
    private func finding(
        for pair: FilePair, counts: CoChangeCounts, targets: Set<String>, _ context: AnalysisContext
    ) -> Finding? {
        let here = targets.contains(pair.first) ? pair.first : pair.second
        guard targets.contains(here) else { return nil }
        let other = here == pair.first ? pair.second : pair.first
        let percent = Int((counts.coupling(pair) * 100).rounded())
        let message = "Changed together with \(other) in \(counts.pairs[pair] ?? 0) commits (\(percent)% coupling) "
            + "over the last \(days(in: context)) days, but neither imports the other: a hidden dependency, "
            + "or logic duplicated between them?"
        return ProjectFinding.make(id, here, 1, message, context)
    }
}

/// Two distinct files, in path order.
struct FilePair: Hashable, Comparable {
    let first: String
    let second: String

    /// Creates a pair, ordering the paths.
    ///
    /// - Parameters:
    ///   - lhs: One path.
    ///   - rhs: Another path.
    init(_ lhs: String, _ rhs: String) {
        (first, second) = lhs < rhs ? (lhs, rhs) : (rhs, lhs)
    }

    /// Orders pairs by their first path, then their second.
    ///
    /// - Parameters:
    ///   - lhs: One pair.
    ///   - rhs: Another pair.
    /// - Returns: Whether `lhs` sorts first.
    static func < (lhs: FilePair, rhs: FilePair) -> Bool {
        (lhs.first, lhs.second) < (rhs.first, rhs.second)
    }
}

/// How often each file and each pair of files changed.
struct CoChangeCounts {
    private(set) var revisions: [String: Int] = [:]
    private(set) var pairs: [FilePair: Int] = [:]

    /// Counts the files and pairs in each commit.
    ///
    /// - Parameter commits: Each commit's changed files.
    init(commits: [Set<String>]) {
        for files in commits {
            let sorted = files.sorted()
            for (offset, path) in sorted.enumerated() {
                revisions[path, default: 0] += 1
                for other in sorted.dropFirst(offset + 1) { pairs[FilePair(path, other), default: 0] += 1 }
            }
        }
    }

    /// Shared commits over the average of the two files' commit counts: 1 when they always change together.
    ///
    /// - Parameter pair: The two files.
    /// - Returns: The coupling, from 0 to 1.
    func coupling(_ pair: FilePair) -> Double {
        let average = Double((revisions[pair.first] ?? 0) + (revisions[pair.second] ?? 0)) / 2
        return average > 0 ? Double(pairs[pair] ?? 0) / average : 0
    }
}

/// Whether two files' coupling is already visible in the dependency graph.
struct Relatedness {
    private let nodeOfFile: [String: String]
    private let dependencies: [String: Set<String>]

    /// Captures the graph.
    ///
    /// - Parameter index: The project's dependency graph.
    init(index: ProjectIndex) {
        nodeOfFile = index.nodeOfFile
        dependencies = index.dependencies
    }

    /// Reports whether two files share a node or one's node imports the other's.
    ///
    /// - Parameters:
    ///   - lhs: One file.
    ///   - rhs: Another file.
    /// - Returns: Whether they're related, treating a file outside the graph as related to everything.
    func connects(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = nodeOfFile[lhs], let right = nodeOfFile[rhs] else { return true }
        let imports = { (from: String, to: String) in dependencies[from]?.contains(to) == true }
        return left == right || imports(left, right) || imports(right, left)
    }
}
