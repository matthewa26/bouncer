import Foundation

/// Supplies every file under a directory, for `bouncer review`'s ad-hoc audit mode.
///
/// Skips a small set of conventionally-noisy directories (`.git`,
/// `node_modules`, build output) plus anything matching a configured exclude
/// glob. This isn't a full `.gitignore` engine, just a practical default.
public struct RecursiveFileWalker: TargetFileProvider {
    private static let alwaysSkippedDirectories: Set<String> = [
        ".git", "node_modules", ".build", "dist", "build", ".venv", "__pycache__", ".git-baseline"
    ]

    private let rootDirectory: URL
    private let excludeFilter: ExcludeFilter

    /// Creates a recursive file walker.
    ///
    /// - Parameters:
    ///   - rootDirectory: The directory to walk.
    ///   - excludeGlobs: Glob patterns, relative to `rootDirectory`, to exclude.
    public init(rootDirectory: URL, excludeGlobs: [String] = []) {
        self.rootDirectory = rootDirectory
        self.excludeFilter = ExcludeFilter(root: rootDirectory, globs: excludeGlobs)
    }

    /// Walks the directory tree and returns every non-excluded regular file.
    ///
    /// - Returns: The matched files' absolute locations.
    /// - Throws: Never, but conforms to `TargetFileProvider`'s throwing signature.
    public func targetFiles() throws -> [URL] {
        guard isDirectory(rootDirectory) else { return excludeFilter.excludes(rootDirectory) ? [] : [rootDirectory] }
        guard let enumerator = makeEnumerator() else { return [] }
        var results: [URL] = []
        for case let url as URL in enumerator {
            visit(url, enumerator: enumerator, results: &results)
        }
        return results
    }

    /// Creates the underlying `FileManager` enumerator.
    ///
    /// - Returns: A directory enumerator rooted at `rootDirectory`.
    private func makeEnumerator() -> FileManager.DirectoryEnumerator? {
        FileManager.default.enumerator(
            at: rootDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )
    }

    /// Handles one enumerated path: skips noisy directories, collects matching files.
    ///
    /// - Parameters:
    ///   - url: The enumerated path.
    ///   - enumerator: The active enumerator, used to skip a directory's contents.
    ///   - results: The accumulated matching files.
    private func visit(_ url: URL, enumerator: FileManager.DirectoryEnumerator, results: inout [URL]) {
        if isAlwaysSkippedDirectory(url) {
            enumerator.skipDescendants()
            return
        }
        guard !isDirectory(url), !excludeFilter.excludes(url) else { return }
        results.append(url)
    }

    /// Checks whether a path is one of the conventionally-skipped directories.
    ///
    /// - Parameter url: The path to check.
    /// - Returns: Whether the path is a directory Bouncer never walks into.
    private func isAlwaysSkippedDirectory(_ url: URL) -> Bool {
        isDirectory(url) && Self.alwaysSkippedDirectories.contains(url.lastPathComponent)
    }

    /// Checks whether a path is a directory.
    ///
    /// - Parameter url: The path to check.
    /// - Returns: Whether the path is a directory.
    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
}
