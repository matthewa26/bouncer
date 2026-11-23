import Foundation
import BouncerCore
import BouncerProject

/// The result the server answers from: each analyzed file's per-file findings and stamp, and the later passes'
/// findings, kept apart so `verify` can replace one file's per-file findings without a new project pass.
struct ResultSnapshot: Sendable {
    /// One analyzed file.
    struct FileState: Sendable {
        /// Where it is.
        let url: URL
        /// Its size and modification time when it was analyzed.
        let stamp: FileStamp?
        /// Its reported per-file findings.
        let findings: [Finding]
    }

    /// The scan that made the result.
    let plan: ScanPlan
    /// How long that scan took.
    let duration: Duration
    /// The saved run's note from that scan: how much it reused.
    let reuseNote: String?
    /// The coverage report, if the scan measured coverage.
    let coverage: CoverageReport?
    /// Each analyzed file, by repo-relative path.
    private(set) var files: [String: FileState]
    /// The project, change, and coverage findings, which only a scan refreshes.
    private(set) var other: [Finding]
    /// When the result was last brought up to date by a scan.
    let producedAt: Date
    /// Bumped by every change, so cached orderings of the findings know they're stale.
    private(set) var generation = 0

    /// Captures a finished scan.
    ///
    /// - Parameters:
    ///   - recorded: The scan's recorded run.
    ///   - plan: The scan.
    ///   - duration: How long it took.
    ///   - reuseNote: The saved run's note.
    init(recorded: RecordedRun, plan: ScanPlan, duration: Duration, reuseNote: String?) {
        (self.plan, self.duration, self.reuseNote, producedAt) = (plan, duration, reuseNote, Date())
        coverage = recorded.result.coverage
        files = Self.states(recorded.files)
        other = recorded.otherFindings
    }

    /// Every reported finding.
    var result: AnalysisResult {
        AnalysisResult(findings: files.values.flatMap(\.findings) + other, coverage: coverage)
    }

    /// How old the result is, in whole seconds.
    var ageSeconds: Int { max(0, Int(Date().timeIntervalSince(producedAt))) }

    /// The reported per-file findings in some files.
    ///
    /// - Parameter paths: Repo-relative paths.
    /// - Returns: Their findings.
    func findings(in paths: [String]) -> [Finding] {
        paths.flatMap { files[$0]?.findings ?? [] }
    }

    /// Replaces some files' per-file findings with a re-analysis's, and drops deleted files with every finding
    /// in them. An analyzed file without a record, such as a binary one, is kept with no findings, so a refresh
    /// doesn't take it for a new file again.
    ///
    /// - Parameters:
    ///   - records: The re-analyzed files' records.
    ///   - analyzed: The files that were re-analyzed.
    ///   - removed: The repo-relative paths of files that are gone or no longer analyzed.
    mutating func replace(_ records: [FileRecord], analyzed: [URL], removing removed: [String]) {
        let gone = Set(removed)
        gone.forEach { files[$0] = nil }
        let repoRoot = plan.repoRoot
        other.removeAll { gone.contains(RepoPath.relative($0.filePath, to: repoRoot)) }
        for url in analyzed {
            files[RepoPath.relative(url, to: repoRoot)] = FileState(url: url, stamp: FileStamp.read(url), findings: [])
        }
        files.merge(Self.states(records)) { _, new in new }
        generation += 1
    }

    /// Keys files' records by path.
    ///
    /// - Parameter records: The records.
    /// - Returns: Each file's state, by repo-relative path.
    private static func states(_ records: [FileRecord]) -> [String: FileState] {
        let pairs = records.map { record in
            let loaded = record.loaded
            return (loaded.path, FileState(url: loaded.file.path, stamp: loaded.stamp, findings: record.reported))
        }
        return Dictionary(pairs) { first, _ in first }
    }

    /// Finds the analyzed files whose size or modification time changed or that vanished, and, when the scan
    /// covered its whole directory, the files that appeared under it.
    ///
    /// - Returns: The changed, deleted, and new files.
    func changedFiles() -> [URL] {
        let changed = files.values.filter { FileStamp.read($0.url) != $0.stamp }.map(\.url)
        guard plan.coversWholeRoot else { return changed }
        let listed = (try? plan.walker.targetFiles()) ?? []
        return changed + listed.filter { files[RepoPath.relative($0, to: plan.repoRoot)] == nil }
    }
}
