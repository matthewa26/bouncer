import Foundation

/// Reads a file's contents, as a seam for tests to fake disk access.
public protocol FileContentsProvider: Sendable {
    /// Reads a file's full contents as text.
    ///
    /// - Parameter url: The file's location.
    /// - Returns: The file's contents.
    /// - Throws: `FileContentsError.binary` for a binary file, or any error reading it.
    func contents(of url: URL) throws -> String
}

/// Why a file's contents aren't analyzable text.
public enum FileContentsError: Error, Equatable {
    /// The file holds a NUL byte, so it's binary (an image, an archive, a compiled file), not source.
    case binary(URL)
}

/// Reads file contents from the real filesystem.
public struct FileSystemContentsProvider: FileContentsProvider {
    /// Creates a filesystem-backed contents provider.
    public init() {}

    /// Reads a file as UTF-8, replacing invalid bytes so text in another encoding (such as Latin-1) is
    /// still analyzed rather than rejected.
    ///
    /// - Parameter url: The file's location.
    /// - Returns: The file's contents.
    /// - Throws: `FileContentsError.binary` if the file holds a NUL byte, or any error reading it.
    public func contents(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard !data.contains(0) else { throw FileContentsError.binary(url) }
        return String(decoding: data, as: UTF8.self)
    }
}
