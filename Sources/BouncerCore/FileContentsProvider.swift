import Foundation

/// Reads a file's contents, as a seam for tests to fake disk access.
public protocol FileContentsProvider: Sendable {
    /// Reads a file's full contents as text.
    ///
    /// - Parameter url: The file's location.
    /// - Returns: The file's contents.
    /// - Throws: If the file can't be read or isn't valid text.
    func contents(of url: URL) throws -> String
}

/// Reads file contents from the real filesystem.
public struct FileSystemContentsProvider: FileContentsProvider {
    /// Creates a filesystem-backed contents provider.
    public init() {}

    /// Reads a file's contents using its detected text encoding.
    ///
    /// - Parameter url: The file's location.
    /// - Returns: The file's contents.
    /// - Throws: If the file can't be read as text.
    public func contents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
