import Foundation
import BouncerCore
import BouncerGit

/// Flags a file that keeps changing for unrelated reasons: divergent change, a sign it holds several
/// responsibilities that should live apart. Off unless configured, since how a team slices commits decides
/// what it finds.
///
/// Without commit topics to read, a commit's reason is approximated by the other modules it touches (Swift
/// targets, Go packages, or folders, leaving out test, generated, and non-code files and the file's own
/// module). Over the last `sinceDays` days, commits touching more than `maxFilesPerCommit` files or more than
/// `maxModulesPerCommit` other modules (sweeping changes) are ignored, commits whose modules are shared or
/// joined by an import are one reason, and a reason needs at least `minCommitsPerReason` commits. A code file
/// is reported when it has at least `minReasons` reasons. Test files, generated files, and manifests
/// (`Package.swift`, `setup.py`, `__init__.py`) aren't reported.
public struct DivergentChangeRule: HistoryRule {
    public let id = "divergent-change"
    /// How many of a reason's modules a message names before eliding the rest.
    private static let shownModules = 3

    /// Creates the rule.
    public init() {}

    /// Runs only when listed under `rules`.
    ///
    /// - Parameter context: Repo-wide state.
    /// - Returns: Whether the rule is configured and enabled.
    public func isEnabled(in context: AnalysisContext) -> Bool {
        context.ruleSettings[id]?.enabled == true
    }

    /// Reads `sinceDays`.
    ///
    /// - Parameter context: Repo-wide state.
    /// - Returns: The window's length, 365 days by default.
    public func days(in context: AnalysisContext) -> Int {
        context.settings(for: id).parameters.int("sinceDays", default: 365)
    }

    /// Flags each checked file that changes alongside several unrelated groups of modules.
    ///
    /// - Parameters:
    ///   - log: The commits read.
    ///   - index: The project's facts, for each file's module.
    ///   - targets: The paths being checked.
    ///   - context: Repo-wide state, with `minReasons`, `minCommitsPerReason`, `maxFilesPerCommit`, and
    ///     `maxModulesPerCommit`.
    /// - Returns: One finding per divergent file.
    public func evaluate(
        _ log: ChangeLog, index: ProjectIndex, targets: Set<String>, context: AnalysisContext
    ) -> [Finding] {
        let parameters = context.settings(for: id).parameters
        let history = CommitHistory(log.within(days: days(in: context)), index: index, parameters: parameters)
        let reasons = ChangeReasons(parameters), minReasons = parameters.int("minReasons", default: 3)
        return history.files(in: targets).compactMap { path -> Finding? in
            let groups = reasons.groups(of: path, in: history)
            guard groups.count >= minReasons else { return nil }
            return ProjectFinding.make(id, path, 1, message(groups, context: context), context)
        }
    }

    /// Explains a divergent file.
    ///
    /// - Parameters:
    ///   - groups: Each reason's modules and commit count, largest first.
    ///   - context: Repo-wide state, for the window.
    /// - Returns: The message.
    private func message(_ groups: [ChangeReasons.Group], context: AnalysisContext) -> String {
        let listed = groups.prefix(ManySubclassesRule.shownNames).map { group -> String in
            let modules = group.modules.map(ProjectUnits.display)
            let shown = modules.prefix(Self.shownModules).joined(separator: " + ")
                + (modules.count > Self.shownModules ? " + …" : "")
            return "with \(shown) (\(group.commits) commits)"
        }.joined(separator: "; ")
        return "Changed for \(groups.count) unrelated reasons over the last \(days(in: context)) days, judging by "
            + "the modules that changed with it: \(listed). Split it so each part changes for one reason."
    }
}

/// Flags a file whose changes keep spreading into many other files across many modules: shotgun surgery,
/// where one change means edits scattered around the code base.
///
/// Over the last `sinceDays` days, a code file with at least `minCommits` commits is reported when, in the
/// median one of them, at least `minFiles` other code files changed across at least `minModules` modules
/// (Swift targets, Go packages, or folders, counting the file's own). Test, generated, and non-code files
/// don't count, commits touching more than `maxFilesPerCommit` files (mass renames, reformatting) are
/// ignored, and test files, generated files, and manifests aren't reported. Off unless configured, since a
/// team that commits whole features at once trips it everywhere.
public struct ShotgunSurgeryRule: HistoryRule {
    public let id = "shotgun-surgery"

    /// Creates the rule.
    public init() {}

    /// Runs only when listed under `rules`.
    ///
    /// - Parameter context: Repo-wide state.
    /// - Returns: Whether the rule is configured and enabled.
    public func isEnabled(in context: AnalysisContext) -> Bool {
        context.ruleSettings[id]?.enabled == true
    }

    /// Reads `sinceDays`.
    ///
    /// - Parameter context: Repo-wide state.
    /// - Returns: The window's length, 180 days by default.
    public func days(in context: AnalysisContext) -> Int {
        context.settings(for: id).parameters.int("sinceDays", default: 180)
    }

    /// Flags each checked file whose median commit spreads widely.
    ///
    /// - Parameters:
    ///   - log: The commits read.
    ///   - index: The project's facts, for each file's module.
    ///   - targets: The paths being checked.
    ///   - context: Repo-wide state, with `minCommits`, `minFiles`, `minModules`, and `maxFilesPerCommit`.
    /// - Returns: One finding per such file.
    public func evaluate(
        _ log: ChangeLog, index: ProjectIndex, targets: Set<String>, context: AnalysisContext
    ) -> [Finding] {
        let parameters = context.settings(for: id).parameters
        let history = CommitHistory(log.within(days: days(in: context)), index: index, parameters: parameters)
        let groups = Dictionary(grouping: history.files(in: targets)) { history.commitNumbers(touching: $0) }
        return groups.values.compactMap { group in finding(group.sorted(), history: history, context: context) }
            .sorted { $0.filePath.path < $1.filePath.path }
    }

    /// Builds one finding for files changed in exactly the same commits, at the first, if their median commit
    /// spreads past both limits.
    ///
    /// - Parameters:
    ///   - paths: The files, sorted.
    ///   - history: The window's commits.
    ///   - context: Repo-wide state, with `minCommits`, `minFiles`, and `minModules`.
    /// - Returns: The finding, or `nil` if its changes stay local.
    private func finding(_ paths: [String], history: CommitHistory, context: AnalysisContext) -> Finding? {
        let parameters = context.settings(for: id).parameters, commits = history.commits(touching: paths[0])
        guard commits.count >= parameters.int("minCommits", default: 5) else { return nil }
        let files = Median.of(commits.map { $0.count - 1 }), modules = Median.of(commits.map(history.modules))
        let limits = (files: parameters.int("minFiles", default: 6), modules: parameters.int("minModules", default: 3))
        guard files >= limits.files, modules >= limits.modules else { return nil }
        let text = message(files, modules, commits.count, paths.dropFirst(), context)
        return ProjectFinding.make(id, paths[0], 1, text, context)
    }

    /// Explains a file whose changes scatter.
    ///
    /// - Parameters:
    ///   - files: The median number of other files changed with it.
    ///   - modules: The median number of modules changed.
    ///   - commits: How many commits touched it.
    ///   - partners: Checked files changed in exactly the same commits, reported here rather than apart.
    ///   - context: Repo-wide state, for the window.
    /// - Returns: The message.
    private func message(
        _ files: Int, _ modules: Int, _ commits: Int, _ partners: ArraySlice<String>, _ context: AnalysisContext
    ) -> String {
        let also = partners.isEmpty ? "" : " The same holds for \(ManySubclassesRule.list(Array(partners))), "
            + "changed in exactly the same commits."
        return "A typical change here also changes \(files) other files across \(modules) modules (the median of "
            + "its \(commits) commits over the last \(days(in: context)) days): each change is scattered. Gather "
            + "the code that changes together, or put the shared decision behind one module." + also
    }
}

/// The window's commits as sets of hand-written, non-test code files, for the change-preventer rules.
struct CommitHistory {
    /// Each kept commit's hand-written, non-test code files.
    let commits: [Set<String>]
    private let byPath: [String: [Int]]
    private let unitOf: (String) -> String
    private let isJudged: (String) -> Bool
    private let neighbors: [String: Set<String>]

    /// Keeps the commits that touch at most `maxFilesPerCommit` files, reduced to their hand-written, non-test
    /// code files.
    ///
    /// - Parameters:
    ///   - commits: The window's commits.
    ///   - index: The project's facts, for modules and generated files.
    ///   - parameters: The rule's parameters, with `maxFilesPerCommit` (30).
    init(_ commits: [GitCommit], index: ProjectIndex, parameters: RuleParameters) {
        let maxFiles = parameters.int("maxFilesPerCommit", default: 30)
        let kept = commits.filter { $0.changes.count <= maxFiles }.map { Self.codeFiles($0, index: index) }
        self.commits = kept
        byPath = kept.enumerated().reduce(into: [:]) { result, item in
            for path in item.element { result[path, default: []].append(item.offset) }
        }
        (unitOf, neighbors) = ({ Self.unit(of: $0, in: index) }, Self.neighbors(in: index))
        isJudged = { index.facts[$0] != nil && !ProjectUnits.isIncidental($0, in: index) && !Self.isManifest($0) }
    }

    /// Reports whether a file is a manifest or package index that every new module touches: `Package.swift`,
    /// `setup.py`, or a Python `__init__.py`.
    ///
    /// - Parameter path: The repo-relative path.
    /// - Returns: Whether the change-preventer rules leave it alone.
    private static func isManifest(_ path: String) -> Bool {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return (name.hasPrefix("Package") && name.hasSuffix(".swift")) || ["setup.py", "__init__.py"].contains(name)
    }

    /// Maps each module to the modules it imports or that import it.
    ///
    /// - Parameter index: The project's dependency graph.
    /// - Returns: Each module's neighbors.
    private static func neighbors(in index: ProjectIndex) -> [String: Set<String>] {
        let module = { (node: String) in
            node.hasPrefix("swift:") || node.hasPrefix("go:") ? node : unit(of: node, in: index)
        }
        return index.edges.reduce(into: [:]) { result, edge in
            let (from, to) = (unit(of: edge.file, in: index), module(edge.to))
            result[from, default: []].insert(to)
            result[to, default: []].insert(from)
        }
    }

    /// Reports whether two sets of modules are related: they share a module, or one imports the other.
    ///
    /// - Parameters:
    ///   - lhs: One commit's modules.
    ///   - rhs: Another's.
    /// - Returns: Whether the commits could be one reason.
    func related(_ lhs: Set<String>, _ rhs: Set<String>) -> Bool {
        !lhs.isDisjoint(with: rhs) || lhs.contains { !(neighbors[$0] ?? []).isDisjoint(with: rhs) }
    }

    /// Reduces a commit to its hand-written, non-test code files.
    ///
    /// - Parameters:
    ///   - commit: The commit.
    ///   - index: The project's facts, for which current files are generated.
    /// - Returns: Its changed code files outside tests and generated code.
    private static func codeFiles(_ commit: GitCommit, index: ProjectIndex) -> Set<String> {
        Set(commit.changes.map(\.path)).filter { path in
            let isGenerated = index.facts[path]?.module.structure.isGenerated == true
            return SourceCode.isCode(path) && !ProjectUnits.isTest(path) && !isGenerated
        }
    }

    /// Names a file's module, falling back to its folder when the module has no name.
    ///
    /// - Parameters:
    ///   - path: The file.
    ///   - index: The project's dependency graph.
    /// - Returns: Its Swift target, Go package, or folder.
    private static func unit(of path: String, in index: ProjectIndex) -> String {
        let unit = ProjectUnits.unit(of: path, in: index)
        return ProjectFinding.display(unit).isEmpty ? "dir:" + ProjectPath.directory(of: path) : unit
    }

    /// Lists the checked files the rules judge: indexed, non-generated code files with commits, by path.
    ///
    /// - Parameter targets: The paths being checked.
    /// - Returns: The files.
    func files(in targets: Set<String>) -> [String] {
        byPath.keys.filter { targets.contains($0) && isJudged($0) }.sorted()
    }

    /// Lists the commits that touched a file.
    ///
    /// - Parameter path: The file.
    /// - Returns: Each commit's non-test code files.
    func commits(touching path: String) -> [Set<String>] {
        commitNumbers(touching: path).map { commits[$0] }
    }

    /// Lists which kept commits touched a file, by position.
    ///
    /// - Parameter path: The file.
    /// - Returns: The commits' positions in `commits`.
    func commitNumbers(touching path: String) -> [Int] { byPath[path] ?? [] }

    /// Counts the modules a commit touched.
    ///
    /// - Parameter commit: The commit's files.
    /// - Returns: The number of distinct modules.
    func modules(_ commit: Set<String>) -> Int { Set(commit.map(unitOf)).count }

    /// Names a file's module.
    ///
    /// - Parameter path: The file.
    /// - Returns: Its Swift target, Go package, or folder.
    func unit(of path: String) -> String { unitOf(path) }
}

/// Groups a file's commits into reasons: commits whose other touched modules overlap are one reason.
struct ChangeReasons {
    /// One reason: the modules that changed with the file for it, and how many commits it took.
    struct Group {
        let modules: [String]
        let commits: Int
    }

    let maxModules: Int
    let minCommits: Int

    /// Reads the grouping limits.
    ///
    /// - Parameter parameters: The rule's parameters, with `maxModulesPerCommit` (3) and
    ///   `minCommitsPerReason` (3).
    init(_ parameters: RuleParameters) {
        maxModules = parameters.int("maxModulesPerCommit", default: 3)
        minCommits = parameters.int("minCommitsPerReason", default: 3)
    }

    /// Groups a file's commits by the other modules they touched.
    ///
    /// - Parameters:
    ///   - path: The file.
    ///   - history: The window's commits.
    /// - Returns: The reasons with at least `minCommits` commits, largest first.
    func groups(of path: String, in history: CommitHistory) -> [Group] {
        let own = history.unit(of: path)
        let reasons = history.commits(touching: path).map { Set($0.map(history.unit)).subtracting([own]) }
            .filter { !$0.isEmpty && $0.count <= maxModules }
        return Self.components(reasons, related: history.related).filter { $0.commits >= minCommits }
            .sorted { ($1.commits, $0.modules.joined()) < ($0.commits, $1.modules.joined()) }
    }

    /// Joins related module sets, counting the sets in each group.
    ///
    /// - Parameters:
    ///   - sets: Each commit's modules.
    ///   - related: Whether two sets of modules share a module or an import.
    /// - Returns: The groups.
    private static func components(
        _ sets: [Set<String>], related: (Set<String>, Set<String>) -> Bool
    ) -> [Group] {
        var groups: [(modules: Set<String>, commits: Int)] = []
        for set in sets {
            let joined = groups.filter { related($0.modules, set) }, apart = groups.filter { !related($0.modules, set) }
            let modules = joined.reduce(set) { $0.union($1.modules) }, commits = joined.map(\.commits)
            groups = apart + [(modules, commits.reduce(1, +))]
        }
        return groups.map { Group(modules: $0.modules.sorted(), commits: $0.commits) }
    }
}

/// The median of a list of counts.
enum Median {
    /// Computes the lower median.
    ///
    /// - Parameter values: The counts.
    /// - Returns: The middle value, or the lower of the two middle values; 0 for an empty list.
    static func of(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[(sorted.count - 1) / 2]
    }
}
