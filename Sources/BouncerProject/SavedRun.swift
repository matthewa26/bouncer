import Foundation
import BouncerCore

/// The result of the last `review`, as `.bouncer-cache/last-run.json` holds it, so the next run analyzes only
/// the files that changed since.
///
/// Each target file's per-file findings are kept apart from the findings of the later passes (project, change,
/// and coverage rules): only the per-file part is ever reused, while the later passes run again every time.
public struct SavedRun: Sendable, Equatable {
    /// What the saved findings depend on besides the files themselves; any difference invalidates the saved run.
    public struct Key: Codable, Sendable, Equatable {
        /// The Bouncer build that produced the run.
        public let version: String
        /// A stable hash of the fully merged config, profile included.
        public let config: String
        /// The reviewed directory's absolute path.
        public let root: String

        /// Creates a key.
        ///
        /// - Parameters:
        ///   - version: The Bouncer build.
        ///   - config: The merged config's hash.
        ///   - root: The reviewed directory's path.
        public init(version: String, config: String, root: String) {
            self.version = version
            self.config = config
            self.root = root
        }
    }

    /// A finding without its file, which its `File` or `PlacedFinding` supplies.
    public struct SavedFinding: Sendable, Equatable {
        /// The rule's ID.
        public let ruleID: String
        /// The severity it was reported at.
        public let severity: Severity
        /// The 1-indexed line.
        public let line: Int
        /// The message.
        public let message: String

        /// Captures a finding, dropping its file.
        ///
        /// - Parameter finding: The finding.
        public init(_ finding: Finding) {
            (ruleID, severity, line, message) = (finding.ruleID, finding.severity, finding.line, finding.message)
        }

        /// Creates a saved finding from its parts.
        ///
        /// - Parameters:
        ///   - ruleID: The rule's ID.
        ///   - severity: The severity.
        ///   - line: The line.
        ///   - message: The message.
        public init(ruleID: String, severity: Severity, line: Int, message: String) {
            (self.ruleID, self.severity, self.line, self.message) = (ruleID, severity, line, message)
        }

        /// Turns the saved finding back into a finding in a file.
        ///
        /// - Parameter file: The file's current location.
        /// - Returns: The finding.
        public func finding(in file: URL) -> Finding {
            Finding(ruleID: ruleID, severity: severity, filePath: file, line: line, message: message)
        }
    }

    /// A finding from a later pass, with its file's repo-relative path.
    public struct PlacedFinding: Sendable, Equatable {
        /// The file's repo-relative path.
        public let path: String
        /// The finding.
        public let finding: SavedFinding

        /// Creates a placed finding.
        ///
        /// - Parameters:
        ///   - path: The file's repo-relative path.
        ///   - finding: The finding.
        public init(path: String, finding: SavedFinding) {
            self.path = path
            self.finding = finding
        }
    }

    /// One analyzed file: what it looked like, and the per-file pass's findings in it.
    public struct File: Sendable, Equatable {
        /// The repo-relative path.
        public let path: String
        /// The size and modification time when it was read.
        public let stamp: FileStamp?
        /// The content hash, or `nil` when its findings can't be reused.
        public let contentHash: String?
        /// The per-file pass's findings, before the baseline and suppression comments.
        public let findings: [SavedFinding]
        /// The indices into `findings` of those the baseline accepted or a comment suppressed.
        public let hidden: [Int]
        /// Whether a change to this file can change other files' findings; see `NeighborFiles`.
        public let affectsNeighbors: Bool
    }

    /// The key the run was saved under.
    public let key: Key
    /// Every analyzed file, in the order the run analyzed them.
    public let files: [File]
    /// The later passes' reported findings: project, change, and coverage findings.
    public let otherFindings: [PlacedFinding]

    /// Creates a saved run from its parts.
    ///
    /// - Parameters:
    ///   - key: The key.
    ///   - files: Every analyzed file.
    ///   - otherFindings: The later passes' reported findings.
    public init(key: Key, files: [File], otherFindings: [PlacedFinding]) {
        self.key = key
        self.files = files
        self.otherFindings = otherFindings
    }

    /// Captures a recorded run for saving.
    ///
    /// - Parameters:
    ///   - key: The key to save it under.
    ///   - recorded: The run.
    ///   - repoRoot: The repository root, which saved paths are relative to.
    public init(key: Key, recorded: RecordedRun, repoRoot: URL) {
        let other = recorded.otherFindings.map { finding in
            PlacedFinding(path: RepoPath.relative(finding.filePath, to: repoRoot), finding: SavedFinding(finding))
        }
        self.init(key: key, files: recorded.files.map(File.init(record:)), otherFindings: other)
    }

    /// How many findings the run reported.
    public var reportedCount: Int {
        files.reduce(otherFindings.count) { $0 + $1.findings.count - $1.hidden.count }
    }
}

extension SavedRun.File {
    /// Captures one file's record. A file with a finding pointing elsewhere is saved as not reusable, since its
    /// findings couldn't be rebuilt from the file alone.
    ///
    /// - Parameter record: The record.
    init(record: FileRecord) {
        let loaded = record.loaded
        let placed = record.findings.allSatisfy { $0.filePath == loaded.file.path }
        self.init(
            path: loaded.path, stamp: loaded.stamp, contentHash: placed ? loaded.contentHash : nil,
            findings: record.findings.map(SavedRun.SavedFinding.init), hidden: record.hidden,
            affectsNeighbors: NeighborFiles.affectsNeighbors(path: loaded.path, contents: loaded.file.contents)
        )
    }
}
