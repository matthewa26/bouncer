import Foundation

/// A target file as the main pass read it, before analyzing it.
public struct LoadedFile: Sendable {
    /// The file.
    public let file: SourceFile
    /// Its repo-relative path, with `/` separators.
    public let path: String
    /// Its content hash, when the run records its files or starts from a saved run.
    public let contentHash: String?
    /// Its size and modification time, read just before its contents, when the run records its files.
    public let stamp: FileStamp?

    /// Creates a loaded file.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - path: Its repo-relative path.
    ///   - contentHash: Its content hash, if computed.
    ///   - stamp: Its size and modification time, if read.
    public init(file: SourceFile, path: String, contentHash: String?, stamp: FileStamp?) {
        self.file = file
        self.path = path
        self.contentHash = contentHash
        self.stamp = stamp
    }
}

/// One target file's part of a run: the per-file pass's findings in it, and which of them weren't reported.
public struct FileRecord: Sendable {
    /// The file as the run read it.
    public let loaded: LoadedFile
    /// The per-file pass's findings, before the baseline and suppression comments were applied.
    public let findings: [Finding]
    /// The indices into `findings` of those the baseline accepted or a comment suppressed, in order.
    public let hidden: [Int]

    /// Creates a file record.
    ///
    /// - Parameters:
    ///   - loaded: The file as the run read it.
    ///   - findings: The per-file pass's findings in it.
    ///   - hidden: The indices of those that weren't reported.
    public init(loaded: LoadedFile, findings: [Finding], hidden: [Int]) {
        self.loaded = loaded
        self.findings = findings
        self.hidden = hidden
    }

    /// The findings that were reported, in order.
    public var reported: [Finding] {
        guard !hidden.isEmpty else { return findings }
        let skipped = Set(hidden)
        return findings.indices.filter { !skipped.contains($0) }.map { findings[$0] }
    }
}

/// A run's result with what a saved run needs to reuse its per-file part.
public struct RecordedRun: Sendable {
    /// The run's result, as `AnalysisEngine.run()` returns it.
    public let result: AnalysisResult
    /// Every analyzed target file's record, in the order the files were analyzed.
    public let files: [FileRecord]
    /// The reported findings that didn't come from the per-file pass: project, change, and coverage findings.
    public let otherFindings: [Finding]

    /// Creates a recorded run.
    ///
    /// - Parameters:
    ///   - result: The run's result.
    ///   - files: Every analyzed target file's record.
    ///   - otherFindings: The reported findings from every later pass.
    public init(result: AnalysisResult, files: [FileRecord], otherFindings: [Finding]) {
        self.result = result
        self.files = files
        self.otherFindings = otherFindings
    }
}

/// An earlier run's per-file findings, which a new run reuses for files that haven't changed since.
public protocol PriorRun: Sendable {
    /// Returns a file's saved per-file findings, if its contents haven't changed since the saved run.
    ///
    /// - Parameter file: A target file of the new run, read and hashed.
    /// - Returns: The saved findings, pointing at the file's current location, or `nil` to analyze it.
    func findings(for file: LoadedFile) -> [Finding]?

    /// Once every target file is read, picks the reused files to analyze after all, because a file their
    /// findings can depend on, such as a package manifest, changed, appeared, or vanished.
    ///
    /// - Parameters:
    ///   - files: Every target file of the new run.
    ///   - reused: The repo-relative paths of the files whose saved findings were reused.
    /// - Returns: The paths to analyze again, and a note saying what was reused.
    func stale(among files: [LoadedFile], reused: Set<String>) -> PriorRunCheck
}

/// Which reused files a `PriorRun` wants analyzed after all.
public struct PriorRunCheck: Sendable {
    /// The repo-relative paths of the reused files to analyze again.
    public let stale: Set<String>
    /// A log note saying how many files were reused and re-analyzed, or why nothing was.
    public let note: String

    /// Creates a check result.
    ///
    /// - Parameters:
    ///   - stale: The reused files to analyze again.
    ///   - note: A log note describing the decision.
    public init(stale: Set<String>, note: String) {
        self.stale = stale
        self.note = note
    }
}
