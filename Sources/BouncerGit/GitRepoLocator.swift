import Foundation

/// Finds the root of the git repository containing a directory.
public enum GitRepoLocator {
    /// Locates the repository root using `git rev-parse --show-toplevel`.
    ///
    /// - Parameter directory: A directory or file inside the candidate repository.
    /// - Returns: The repository root, or `nil` if `directory` isn't inside a git repo.
    public static func repoRoot(startingAt directory: URL) -> URL? {
        let arguments = ["rev-parse", "--show-toplevel"]
        let startDirectory = containingDirectory(of: directory)
        guard let path = ProcessRunner.run("git", arguments, currentDirectory: startDirectory) else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Resolves a path to a real directory, since a subprocess can't `chdir` into a plain file.
    ///
    /// - Parameter path: A directory or file.
    /// - Returns: `path` itself if it's already a directory, otherwise its parent directory.
    private static func containingDirectory(of path: URL) -> URL {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue ? path.deletingLastPathComponent() : path
    }
}
