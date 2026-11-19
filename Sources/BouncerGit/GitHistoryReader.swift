import Foundation

/// Reads a repository's recent history in one `git log` call, for the churn-based project rules.
public enum GitHistoryReader {
    /// The most commits read, however long the window, to bound the cost on very active repositories.
    public static let defaultMaxCommits = 5_000

    /// Reads the non-merge commits from the last `days` days before the newest commit, with each file's
    /// changes filed under its current path across renames.
    ///
    /// The window is counted back from `HEAD`'s commit date rather than today, so a dormant repository still
    /// has history to read and the result doesn't depend on when it's run.
    ///
    /// - Parameters:
    ///   - repoRoot: The repository root; paths in the result are relative to it.
    ///   - days: The window's length in days.
    ///   - maxCommits: The most commits to read.
    /// - Returns: The commits, newest first, or `nil` if `repoRoot` isn't a git repository with commits.
    public static func commits(in repoRoot: URL, days: Int, maxCommits: Int = defaultMaxCommits) -> [GitCommit]? {
        guard let head = headDate(in: repoRoot) else { return nil }
        let since = head.addingTimeInterval(-Double(days) * 86_400)
        let arguments = [
            "-c", "core.quotePath=false", "log", "--use-mailmap", "--no-merges", "--numstat", "-M",
            GitLogParser.format, "--since=\(iso8601(since))", "--max-count=\(maxCommits)", "HEAD"
        ]
        guard let output = ProcessRunner.run("git", arguments, currentDirectory: repoRoot) else { return nil }
        return RenameFollower.follow(GitLogParser.commits(from: output))
    }

    /// Reads `HEAD`'s commit date.
    ///
    /// - Parameter repoRoot: The repository root.
    /// - Returns: The date, or `nil` without a repository or commits.
    private static func headDate(in repoRoot: URL) -> Date? {
        let arguments = ["log", "-1", "--format=%ct", "HEAD"]
        guard let output = ProcessRunner.run("git", arguments, currentDirectory: repoRoot),
              let seconds = TimeInterval(output) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Formats a date the way `git log --since` reads it unambiguously.
    ///
    /// - Parameter date: The date.
    /// - Returns: An ISO 8601 UTC timestamp.
    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

/// Reads what a commit is about to change, and older versions of files, for the check-mode change rules.
public enum GitChangeReader {
    /// Lists the staged changes with their line counts, following renames.
    ///
    /// - Parameter repoRoot: The repository root.
    /// - Returns: The staged changes, or `nil` if git fails.
    public static func stagedChanges(in repoRoot: URL) -> [GitFileChange]? {
        let arguments = ["-c", "core.quotePath=false", "diff", "--cached", "--numstat", "-M"]
        let output = ProcessRunner.run("git", arguments, currentDirectory: repoRoot)
        return output.map { GitLogParser.changes(from: $0[...]) }
    }

    /// Finds the merge base of `HEAD` and the first of several refs that exists.
    ///
    /// - Parameters:
    ///   - refs: Candidate refs, in order of preference, such as `origin/main` then `main`.
    ///   - repoRoot: The repository root.
    /// - Returns: The ref used and the merge base's hash, or `nil` if none of them has one.
    public static func mergeBase(of refs: [String], in repoRoot: URL) -> (ref: String, commit: String)? {
        for ref in refs {
            let arguments = ["merge-base", "HEAD", ref]
            if let commit = ProcessRunner.run("git", arguments, currentDirectory: repoRoot), !commit.isEmpty {
                return (ref, commit)
            }
        }
        return nil
    }

    /// Reads a file's contents at a commit.
    ///
    /// - Parameters:
    ///   - path: The repo-relative path, with `/` separators.
    ///   - commit: The commit or ref.
    ///   - repoRoot: The repository root.
    /// - Returns: The contents, or `nil` if the file didn't exist there or isn't UTF-8 text.
    public static func contents(of path: String, at commit: String, in repoRoot: URL) -> String? {
        ProcessRunner.output("git", ["show", "\(commit):\(path)"], currentDirectory: repoRoot)
    }
}
