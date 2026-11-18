import Foundation

/// Supplies exactly the files it was given, bypassing git or a directory walk.
///
/// Backs `bouncer check --files`/`--stdin`, the agent post-edit self-check
/// entry point: an agent can hand Bouncer the file it just edited without
/// needing a git-staged diff.
public struct ExplicitFileListProvider: TargetFileProvider {
    private let files: [URL]

    /// Creates a provider over a fixed list of files.
    ///
    /// - Parameter files: The files to analyze.
    public init(files: [URL]) {
        self.files = files
    }

    /// Returns the fixed file list this provider was created with.
    ///
    /// - Returns: The files to analyze.
    public func targetFiles() throws -> [URL] {
        files
    }
}
