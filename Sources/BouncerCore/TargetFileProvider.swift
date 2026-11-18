import Foundation

/// Supplies the set of files an `AnalysisEngine` run should analyze.
///
/// `check` and `review` differ only in how this list is produced:
/// git-staged files for one, a recursive directory walk for the other - so
/// `AnalysisEngine` itself stays mode-agnostic.
public protocol TargetFileProvider: Sendable {
    /// Returns the files to analyze for this run.
    ///
    /// - Returns: The files' locations on disk.
    /// - Throws: If the underlying source (git, the filesystem) can't be read.
    func targetFiles() throws -> [URL]
}
