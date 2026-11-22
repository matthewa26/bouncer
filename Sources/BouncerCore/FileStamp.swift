import Foundation

/// A file's size and modification time: a cheap way to tell, without reading it, that a file may have changed.
public struct FileStamp: Codable, Sendable, Equatable {
    private static let nanosecondsPerSecond = 1_000_000_000.0

    /// The file's size in bytes.
    public let size: Int64
    /// The file's modification time, in nanoseconds since 1970, rounded.
    public let modified: Int64

    /// Creates a stamp.
    ///
    /// - Parameters:
    ///   - size: The file's size in bytes.
    ///   - modified: Its modification time, in nanoseconds since 1970.
    public init(size: Int64, modified: Int64) {
        self.size = size
        self.modified = modified
    }

    /// Reads a file's stamp from the filesystem, through a fresh URL so no cached value is returned.
    ///
    /// - Parameter url: The file.
    /// - Returns: Its stamp, or `nil` if its attributes can't be read.
    public static func read(_ url: URL) -> FileStamp? {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let values = try? URL(fileURLWithPath: url.path).resourceValues(forKeys: keys),
              let size = values.fileSize, let date = values.contentModificationDate else { return nil }
        let nanoseconds = (date.timeIntervalSince1970 * nanosecondsPerSecond).rounded()
        return FileStamp(size: Int64(size), modified: Int64(nanoseconds))
    }
}
