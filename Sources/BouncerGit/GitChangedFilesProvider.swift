import Foundation
import BouncerCore

/// Supplies the files changed since a git revision, for `bouncer review --changed-since`.
///
/// A file counts as changed when it differs between the revision and the working tree - committed since,
/// staged, or unstaged - or is untracked and not ignored. Deleted files are left out, and a renamed file is
/// listed under its new path. The candidates then pass the same skipped-folder, hidden-file, and exclude
/// rules as `RecursiveFileWalker`, and only files under the reviewed directory are kept. The list is
/// resolved once, when the provider is created, so a bad revision fails before analysis starts and the
/// command can log how many files it found.
public struct GitChangedFilesProvider: TargetFileProvider {
    private let walker: RecursiveFileWalker
    private let files: [URL]

    /// Creates a provider, asking git for the changed files.
    ///
    /// - Parameters:
    ///   - revision: The revision to compare the working tree against, such as `main` or `HEAD~3`.
    ///   - rootDirectory: The reviewed directory or file; only changed files under it are listed.
    ///   - excludeGlobs: Glob patterns, relative to `rootDirectory`, to exclude.
    /// - Throws: `GitError` if `rootDirectory` isn't in a git repository, `revision` doesn't name a commit,
    ///   or git fails.
    public init(revision: String, rootDirectory: URL, excludeGlobs: [String] = []) throws {
        let walker = RecursiveFileWalker(rootDirectory: rootDirectory, excludeGlobs: excludeGlobs)
        let query = ChangedPathsQuery(rootDirectory)
        let urls = try query.changedPaths(since: revision).map { RepoPath.url($0, in: query.directory) }
        self.walker = walker
        self.files = urls.filter(walker.admits)
    }

    /// Returns the changed files found when the provider was created.
    ///
    /// - Returns: The files' absolute locations, sorted by path.
    public func targetFiles() throws -> [URL] {
        files
    }

    /// Limits rules in a `.github` CI file to the supply-chain rules, as the directory walk does.
    ///
    /// - Parameter url: One of the provider's files.
    /// - Returns: The walker's rule scope for the file.
    public func ruleScope(for url: URL) -> Set<String>? {
        walker.ruleScope(for: url)
    }
}

/// Asks git which paths under a directory changed since a revision.
private struct ChangedPathsQuery {
    /// The directory git runs in, whose relative paths it reports: the reviewed directory, or a reviewed
    /// file's folder.
    let directory: URL
    /// The pathspec limiting the query: `.` for a directory, or a reviewed file's name.
    let pathspec: String

    /// Scopes a query to a reviewed directory or file.
    ///
    /// - Parameter root: The reviewed directory or file.
    init(_ root: URL) {
        var isDirectory: ObjCBool = false
        let isFile = FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        directory = isFile ? root.deletingLastPathComponent() : root
        pathspec = isFile ? root.lastPathComponent : "."
    }

    /// Lists the changed and untracked paths, relative to `directory` with `/` separators.
    ///
    /// `-z` keeps paths with spaces or non-ASCII characters exactly as they are, unquoted.
    ///
    /// - Parameter revision: The revision to compare against.
    /// - Returns: The paths, sorted and without duplicates.
    /// - Throws: `GitError` if there's no repository, the revision is unknown, or git fails.
    func changedPaths(since revision: String) throws -> [String] {
        guard GitRepoLocator.repoRoot(startingAt: directory) != nil else {
            throw GitError.notARepository(directory.standardizedFileURL.path)
        }
        let commit = try resolve(revision)
        let changed = try paths(["diff", "--name-only", "-z", "--relative", "--diff-filter=d", commit, "--", pathspec])
        let untracked = try paths(["ls-files", "--others", "--exclude-standard", "-z", "--", pathspec])
        return Set(changed + untracked).sorted()
    }

    /// Resolves a revision to its commit, so a typo fails clearly and a name starting with `-` can't be read
    /// as an option by the later commands.
    ///
    /// - Parameter revision: The revision as given.
    /// - Returns: The commit's full hash.
    /// - Throws: `GitError.unknownRevision` if it doesn't name a commit.
    private func resolve(_ revision: String) throws -> String {
        let arguments = ["rev-parse", "--verify", "--quiet", "--end-of-options", "\(revision)^{commit}"]
        guard let commit = ProcessRunner.run("git", arguments, currentDirectory: directory), !commit.isEmpty else {
            throw GitError.unknownRevision(revision)
        }
        return commit
    }

    /// Runs a git query that prints NUL-separated paths.
    ///
    /// - Parameter arguments: The git subcommand and its arguments.
    /// - Returns: The printed paths.
    /// - Throws: `GitError.commandFailed` if git fails.
    private func paths(_ arguments: [String]) throws -> [String] {
        guard let output = ProcessRunner.output("git", arguments, currentDirectory: directory) else {
            throw GitError.commandFailed
        }
        return output.split(separator: "\0").map(String.init)
    }
}
