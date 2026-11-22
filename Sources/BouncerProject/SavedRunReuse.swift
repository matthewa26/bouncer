import Foundation
import BouncerCore

/// Reuses a saved run's per-file findings for files whose contents haven't changed.
///
/// A file is reused only when its content hash still matches, so a file that was touched but not edited is
/// reused too, and an edit that keeps the size and modification time is still caught. Files under a changed
/// manifest or entry point are analyzed again (see `NeighborFiles`); new files are analyzed, and deleted ones
/// drop out because the new run never lists them.
public struct SavedRunReuse: PriorRun {
    private let files: [String: SavedRun.File]

    /// Prepares to reuse a saved run.
    ///
    /// - Parameter run: The saved run, whose key already matched the new run's.
    public init(_ run: SavedRun) {
        files = Dictionary(run.files.map { ($0.path, $0) }) { first, _ in first }
    }

    /// Returns a file's saved findings when its content hash matches the saved one.
    ///
    /// - Parameter file: A target file of the new run.
    /// - Returns: The saved findings in the file's current location, or `nil` to analyze it.
    public func findings(for file: LoadedFile) -> [Finding]? {
        guard let saved = files[file.path], let hash = saved.contentHash, hash == file.contentHash else { return nil }
        return saved.findings.map { $0.finding(in: file.file.path) }
    }

    /// Picks the reused files under a manifest or entry point that changed, appeared, or vanished.
    ///
    /// - Parameters:
    ///   - current: Every target file of the new run.
    ///   - reused: The paths of the files whose saved findings were reused.
    /// - Returns: The reused files to analyze again, and a note counting what was reused and why the rest wasn't.
    public func stale(among current: [LoadedFile], reused: Set<String>) -> PriorRunCheck {
        let currentPaths = Set(current.map(\.path))
        let deleted = files.values.filter { !currentPaths.contains($0.path) }
        let changed = current.filter { !reused.contains($0.path) }
        let reach = Set((changed.filter(affectsNeighbors).map(\.path) + deleted.filter(\.affectsNeighbors).map(\.path))
            .map(NeighborFiles.directory))
        let stale: Set<String> = reach.isEmpty ? [] : reused.filter { NeighborFiles.isUnder($0, anyOf: reach) }
        let added = changed.filter { files[$0.path] == nil }.count
        let tally = Tally(total: current.count, reused: reused.count - stale.count, stale: stale.count, added: added)
        return PriorRunCheck(stale: stale, note: tally.note(deleted: deleted.count))
    }

    /// Reports whether a changed or new file's change can reach other files, judging by its old and new contents.
    ///
    /// - Parameter file: The file.
    /// - Returns: Whether it is, or was, a manifest or entry point.
    private func affectsNeighbors(_ file: LoadedFile) -> Bool {
        files[file.path]?.affectsNeighbors == true
            || NeighborFiles.affectsNeighbors(path: file.path, contents: file.file.contents)
    }

    /// Counts what a run reused, for its log note.
    private struct Tally {
        /// Every target file.
        let total: Int
        /// Files whose saved findings were kept.
        let reused: Int
        /// Unchanged files analyzed again because a manifest or entry point above them changed.
        let stale: Int
        /// Files the saved run didn't have.
        let added: Int

        /// The note.
        ///
        /// - Parameter deleted: How many files the saved run had that are gone.
        /// - Returns: The note.
        func note(deleted: Int) -> String {
            let edited = total - reused - stale - added
            return "saved run: reused findings for \(reused) of \(total) file(s); analyzed \(edited) changed, "
                + "\(added) new, and \(stale) near a changed manifest or entry point; dropped \(deleted) deleted"
        }
    }
}

/// Stands in for a saved run that can't be used, so the run analyzes every file and says why.
public struct UnusableSavedRun: PriorRun {
    /// Why the saved run can't be used, such as "the config changed since the saved run".
    public let reason: String

    /// Creates a stand-in.
    ///
    /// - Parameter reason: Why the saved run can't be used.
    public init(reason: String) {
        self.reason = reason
    }

    /// Reuses nothing.
    ///
    /// - Parameter file: Unused.
    /// - Returns: `nil`.
    public func findings(for file: LoadedFile) -> [Finding]? {
        nil
    }

    /// Re-analyzes nothing more, and notes why every file was analyzed.
    ///
    /// - Parameters:
    ///   - current: Unused.
    ///   - reused: Unused; always empty.
    /// - Returns: No stale files, and the note.
    public func stale(among current: [LoadedFile], reused: Set<String>) -> PriorRunCheck {
        PriorRunCheck(stale: [], note: "saved run not used: \(reason); analyzed every file")
    }
}
