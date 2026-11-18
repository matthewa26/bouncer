import Foundation

/// Decides whether a file matches a configured `exclude` glob, relative to a root directory.
///
/// Shared by every way Bouncer picks its target files, so `review`'s directory
/// walk and `check`'s staged or explicit file lists honor `exclude` identically.
public struct ExcludeFilter: Sendable {
    private let rootPath: String
    private let globs: [String]

    /// Creates an exclude filter.
    ///
    /// - Parameters:
    ///   - root: The directory the globs are relative to.
    ///   - globs: Glob patterns to exclude.
    public init(root: URL, globs: [String]) {
        self.rootPath = root.standardizedFileURL.path
        self.globs = globs
    }

    /// Checks whether a path matches any exclude glob.
    ///
    /// - Parameter url: The path to check.
    /// - Returns: Whether the path should be excluded.
    public func excludes(_ url: URL) -> Bool {
        guard !globs.isEmpty else { return false }
        let relative = relativePath(of: url)
        return globs.contains { GlobMatcher.matches(path: relative, pattern: $0) }
    }

    /// Expresses a path relative to the root directory.
    ///
    /// - Parameter url: The absolute path.
    /// - Returns: The path relative to the root, or the absolute path if it lies outside it.
    private func relativePath(of url: URL) -> String {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
    }
}

/// Wraps another file provider, dropping any file an `ExcludeFilter` excludes.
public struct ExcludingFileProvider: TargetFileProvider {
    private let base: TargetFileProvider
    private let filter: ExcludeFilter

    /// Creates an excluding wrapper around a file provider.
    ///
    /// - Parameters:
    ///   - base: The provider whose files to filter.
    ///   - filter: The exclude rules to apply.
    public init(base: TargetFileProvider, filter: ExcludeFilter) {
        self.base = base
        self.filter = filter
    }

    /// Returns the base provider's files, minus any that are excluded.
    ///
    /// - Returns: The remaining files.
    /// - Throws: Whatever the base provider throws.
    public func targetFiles() throws -> [URL] {
        try base.targetFiles().filter { !filter.excludes($0) }
    }
}
