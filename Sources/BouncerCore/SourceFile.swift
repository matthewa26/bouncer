import Foundation

/// A single file handed to an analyzer, already read from disk.
///
/// Reading the file once at the boundary (rather than in each `Rule`) is what
/// lets `Rule` and `LanguageAnalyzer` implementations stay pure functions over
/// in-memory data, which is what makes them easy to unit test.
public struct SourceFile: Sendable {
    /// The file's location on disk.
    public let path: URL

    /// The detected language for this file.
    public let language: Language

    /// The file's full contents.
    public let contents: String

    /// The file split into lines, computed once and reused by every rule.
    public let lines: [Substring]

    /// Creates a source file from already-read contents.
    ///
    /// - Parameters:
    ///   - path: The file's location on disk.
    ///   - language: The detected language for this file.
    ///   - contents: The file's full contents.
    public init(path: URL, language: Language, contents: String) {
        self.path = path
        self.language = language
        self.contents = contents
        self.lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
    }
}
