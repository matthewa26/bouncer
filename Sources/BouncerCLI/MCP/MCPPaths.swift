import Foundation

/// How the server reads the paths agents pass it: relative to the repository root, or absolute.
enum MCPPaths {
    /// Resolves a path an agent passed.
    ///
    /// - Parameters:
    ///   - path: The path, relative to the repository root or absolute.
    ///   - repoRoot: The repository root.
    /// - Returns: The absolute, standardized location.
    static func resolve(_ path: String, repoRoot: URL) -> URL {
        // An absolute path ignores the base, on every platform.
        URL(fileURLWithPath: path, relativeTo: repoRoot).absoluteURL.standardizedFileURL
    }

    /// Whether a location is the root or under it.
    ///
    /// - Parameters:
    ///   - url: The location.
    ///   - root: The root.
    /// - Returns: Whether `url`'s path components start with `root`'s.
    static func isInside(_ url: URL, _ root: URL) -> Bool {
        url.standardizedFileURL.pathComponents.starts(with: root.standardizedFileURL.pathComponents)
    }
}
