import ArgumentParser
import Foundation
import BouncerCore
import BouncerGit

/// The files `review` analyzes, the files its project rules index, and how the verbose log describes them.
///
/// With `--changed-since`, only the changed files are analyzed, but the project rules still index every file
/// under the reviewed directory, so cross-file rules such as `unused-export` or import cycles see the whole
/// module graph (mostly from the facts cache) and report only the findings that land in a changed file.
struct ReviewFileSelection {
    /// The files whose findings are reported.
    let targets: TargetFileProvider
    /// The files the project rules index.
    let index: TargetFileProvider
    /// The verbose log's line describing the analyzed files.
    let logLine: String

    /// Chooses the files for one `review` run.
    ///
    /// - Parameters:
    ///   - rootDirectory: The reviewed directory.
    ///   - excludeGlobs: Every exclude glob, from the command line and the config.
    ///   - changedSince: The `--changed-since` revision, if given.
    /// - Returns: The selection.
    /// - Throws: `ExitCode(2)`, after printing why, if the changed files can't be listed.
    static func resolve(rootDirectory: URL, excludeGlobs: [String], changedSince: String?) throws -> Self {
        let walker = RecursiveFileWalker(rootDirectory: rootDirectory, excludeGlobs: excludeGlobs)
        let everyFile = "files: every file under \(rootDirectory.path), excluding \(excludeGlobs.count) glob(s)"
        guard let changedSince else { return Self(targets: walker, index: walker, logLine: everyFile) }
        let changed = try changedFiles(since: changedSince, rootDirectory: rootDirectory, excludeGlobs: excludeGlobs)
        let count = try changed.targetFiles().count
        let line = "files: \(count) file\(count == 1 ? "" : "s") changed since \(changedSince) under \(rootDirectory.path)"
        return Self(targets: changed, index: walker, logLine: line)
    }

    /// Asks git for the changed files, turning a git failure into a clear message and exit code 2.
    ///
    /// - Parameters:
    ///   - revision: The `--changed-since` revision.
    ///   - rootDirectory: The reviewed directory.
    ///   - excludeGlobs: Every exclude glob.
    /// - Returns: The changed-files provider.
    /// - Throws: `ExitCode(2)` if git can't list them.
    private static func changedFiles(
        since revision: String, rootDirectory: URL, excludeGlobs: [String]
    ) throws -> GitChangedFilesProvider {
        do {
            return try GitChangedFilesProvider(revision: revision, rootDirectory: rootDirectory, excludeGlobs: excludeGlobs)
        } catch let error as GitError {
            FileHandle.standardError.write(Data("bouncer: \(error.description)\n".utf8))
            throw ExitCode(2)
        }
    }
}
