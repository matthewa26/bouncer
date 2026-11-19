import Foundation
import BouncerCore
import BouncerGit

/// Supplies commit history to the history rules; a protocol so tests can supply a fixed history.
public protocol HistorySource: Sendable {
    /// Reads recent commits.
    ///
    /// - Parameters:
    ///   - repoRoot: The repository root.
    ///   - days: How many days of history, counted back from the newest commit.
    /// - Returns: The commits, newest first, or `nil` without a repository.
    func commits(in repoRoot: URL, days: Int) -> [GitCommit]?
}

/// Reads history with one `git log` call.
public struct GitLogHistorySource: HistorySource {
    /// Creates the source.
    public init() {}

    /// Reads recent commits with `GitHistoryReader`.
    ///
    /// - Parameters:
    ///   - repoRoot: The repository root.
    ///   - days: How many days of history.
    /// - Returns: The commits, newest first, or `nil` without a repository.
    public func commits(in repoRoot: URL, days: Int) -> [GitCommit]? {
        GitHistoryReader.commits(in: repoRoot, days: days)
    }
}

/// Supplies the staged diff and base-branch file versions to the change rules.
public protocol ChangeSource: Sendable {
    /// Lists the staged changes.
    ///
    /// - Parameter repoRoot: The repository root.
    /// - Returns: The changes, or `nil` if git fails.
    func stagedChanges(in repoRoot: URL) -> [GitFileChange]?

    /// Finds the merge base of `HEAD` and the first of several refs that exists.
    ///
    /// - Parameters:
    ///   - refs: Candidate refs, in order of preference.
    ///   - repoRoot: The repository root.
    /// - Returns: The ref used and the merge base's hash, or `nil` if none resolves.
    func mergeBase(of refs: [String], in repoRoot: URL) -> (ref: String, commit: String)?

    /// Reads a file's contents at a commit.
    ///
    /// - Parameters:
    ///   - path: The repo-relative path.
    ///   - commit: The commit.
    ///   - repoRoot: The repository root.
    /// - Returns: The contents, or `nil` if the file didn't exist there.
    func contents(of path: String, at commit: String, in repoRoot: URL) -> String?
}

/// Reads changes and old file versions with git.
public struct GitChangeSource: ChangeSource {
    /// Creates the source.
    public init() {}

    /// Lists the staged changes with `git diff --cached --numstat`.
    ///
    /// - Parameter repoRoot: The repository root.
    /// - Returns: The changes, or `nil` if git fails.
    public func stagedChanges(in repoRoot: URL) -> [GitFileChange]? {
        GitChangeReader.stagedChanges(in: repoRoot)
    }

    /// Finds a merge base with `git merge-base`.
    ///
    /// - Parameters:
    ///   - refs: Candidate refs, in order of preference.
    ///   - repoRoot: The repository root.
    /// - Returns: The ref used and the merge base's hash, or `nil` if none resolves.
    public func mergeBase(of refs: [String], in repoRoot: URL) -> (ref: String, commit: String)? {
        GitChangeReader.mergeBase(of: refs, in: repoRoot)
    }

    /// Reads an old version of a file with `git show`.
    ///
    /// - Parameters:
    ///   - path: The repo-relative path.
    ///   - commit: The commit.
    ///   - repoRoot: The repository root.
    /// - Returns: The contents, or `nil` if the file didn't exist there.
    public func contents(of path: String, at commit: String, in repoRoot: URL) -> String? {
        GitChangeReader.contents(of: path, at: commit, in: repoRoot)
    }
}

/// The commits the history rules share, read once per run.
public struct ChangeLog: Sendable {
    /// Every commit read, newest first.
    public let commits: [GitCommit]

    /// Creates a change log.
    ///
    /// - Parameter commits: The commits, newest first.
    public init(commits: [GitCommit]) {
        self.commits = commits
    }

    /// Lists the commits from the last `days` days, counted back from the newest one.
    ///
    /// - Parameter days: The window's length.
    /// - Returns: The commits in the window, in their original order.
    public func within(days: Int) -> [GitCommit] {
        guard let newest = commits.map(\.date).max() else { return [] }
        let start = newest.addingTimeInterval(-Double(days) * 86_400)
        return commits.filter { $0.date >= start }
    }

    /// Groups commits by the files they touched, keeping only files that pass a filter.
    ///
    /// - Parameters:
    ///   - commits: The commits.
    ///   - include: Which repo-relative paths to keep.
    /// - Returns: Each kept path's commits, each commit listed once per path.
    static func commitsByPath(_ commits: [GitCommit], where include: (String) -> Bool) -> [String: [GitCommit]] {
        var result: [String: [GitCommit]] = [:]
        for commit in commits {
            for path in Set(commit.changes.map(\.path)) where include(path) { result[path, default: []].append(commit) }
        }
        return result
    }
}

/// Recognizes source code by extension, so docs and config files stay out of the history rules.
enum SourceCode {
    /// Reports whether a path has a known programming language's extension.
    ///
    /// - Parameter path: The repo-relative path.
    /// - Returns: Whether the file is code.
    static func isCode(_ path: String) -> Bool {
        if case .other = Language.from(fileExtension: (path as NSString).pathExtension) { return false }
        return true
    }

    /// Reports whether a file says it's generated, in a header such as `// Code generated … DO NOT EDIT.`,
    /// `@generated`, or `Automatically generated by …`, within its first ten lines.
    ///
    /// - Parameter file: The file.
    /// - Returns: Whether the file is generated code, which nobody simplifies by hand.
    static func isGenerated(_ file: SourceFile) -> Bool {
        FactText.isGenerated(file.contents)
    }
}
