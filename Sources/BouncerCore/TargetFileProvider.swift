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

    /// The only rules allowed to report in one of the provider's files, such as a CI workflow the walker
    /// lists for the supply-chain rules alone; see the default implementation.
    ///
    /// - Parameter url: One of the provider's files.
    /// - Returns: The rule IDs that may report in it, or `nil` when every rule may.
    func ruleScope(for url: URL) -> Set<String>?
}

extension TargetFileProvider {
    /// The only rules allowed to report in a file, for a file the provider surfaces solely for those rules.
    ///
    /// - Parameter url: One of the provider's files.
    /// - Returns: The rule IDs that may report in it, or `nil` when every rule may (the default).
    public func ruleScope(for url: URL) -> Set<String>? {
        nil
    }
}
