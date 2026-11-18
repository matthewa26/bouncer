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

/// An error running a git command this provider depends on.
public enum GitError: Error {
    case commandFailed
}
