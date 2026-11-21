import Foundation

/// Decides whether a file is left out of analysis: a license or notice file, which is legal text rather than
/// code, or a path matching a configured `exclude` glob, relative to a root directory.
///
/// Shared by every way Bouncer picks its target files, so `review`'s directory
/// walk and `check`'s staged or explicit file lists honor `exclude` identically.
public struct ExcludeFilter: Sendable {
    private static let legalFileNames: Set<String> = ["LICENSE", "LICENCE", "COPYING", "NOTICE", "UNLICENSE"]
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

    /// Checks whether a path is a license or notice file, or matches any exclude glob.
    ///
    /// - Parameter url: The path to check.
    /// - Returns: Whether the path should be excluded.
    public func excludes(_ url: URL) -> Bool {
        if Self.isLegalFile(url) { return true }
        guard !globs.isEmpty else { return false }
        let relative = relativePath(of: url)
        return globs.contains { GlobMatcher.matches(path: relative, pattern: $0) }
    }

    /// Recognizes license and notice files by name: `LICENSE`, `LICENCE`, `COPYING`, `NOTICE`, or `UNLICENSE`,
    /// in any case, alone or followed by an extension or suffix (`LICENSE.md`, `COPYING.txt`, `LICENSE-MIT`).
    /// A source file that merely starts with one, such as `license.ts` or `LicenseView.swift`, isn't one.
    ///
    /// - Parameter url: The path to check.
    /// - Returns: Whether the file is a license or notice file.
    static func isLegalFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        let stem = String(name.prefix { $0 != "." && $0 != "-" && $0 != "_" }).uppercased()
        guard legalFileNames.contains(stem) else { return false }
        let rest = name.dropFirst(stem.count)
        return rest.isEmpty || !["swift", "ts", "tsx", "js", "jsx", "py", "go"].contains(url.pathExtension.lowercased())
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

    /// Passes the base provider's rule scope through.
    ///
    /// - Parameter url: One of the files.
    /// - Returns: Whatever the base provider limits the file's rules to.
    public func ruleScope(for url: URL) -> Set<String>? {
        base.ruleScope(for: url)
    }
}
