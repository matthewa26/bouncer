import Foundation
import BouncerCore

/// Supplies the set of files staged for commit, for `bouncer check`'s default mode.
public struct GitStagedFilesProvider: TargetFileProvider {
    private let repoRoot: URL

    /// Creates a staged-files provider.
    ///
    /// - Parameter repoRoot: The repository to query.
    public init(repoRoot: URL) {
        self.repoRoot = repoRoot
    }

    /// Lists every added, copied, or modified file staged for commit.
    ///
    /// - Returns: The staged files' absolute locations.
    /// - Throws: If `git` isn't available or the query fails.
    public func targetFiles() throws -> [URL] {
        let arguments = ["diff", "--cached", "--name-only", "--diff-filter=ACM"]
        guard let output = ProcessRunner.run("git", arguments, currentDirectory: repoRoot) else {
            throw GitError.commandFailed
        }
        return output.split(separator: "\n").map { repoRoot.appendingPathComponent(String($0)) }
    }
}

/// An error running a git command a file provider depends on.
public enum GitError: Error, Equatable, CustomStringConvertible, LocalizedError {
    /// git isn't on `PATH`, or a query exited non-zero.
    case commandFailed
    /// The directory, whose path this carries, isn't inside a git repository.
    case notARepository(String)
    /// The revision, as given, doesn't name a commit in the repository.
    case unknownRevision(String)

    /// A human-readable explanation, shown by the CLI when the error ends a command.
    public var description: String {
        switch self {
        case .commandFailed:
            return "A git command failed; check that git is installed and on PATH."
        case .notARepository(let path):
            return "\(path) isn't inside a git repository, which --changed-since needs."
        case .unknownRevision(let revision):
            return "Unknown revision \"\(revision)\": it doesn't name a commit in this repository."
        }
    }

    /// The same text as `description`, for `localizedDescription`.
    public var errorDescription: String? { description }
}
