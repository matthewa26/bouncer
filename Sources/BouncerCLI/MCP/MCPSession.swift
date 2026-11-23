import Foundation
import BouncerCore
import BouncerProject
import BouncerReporting

/// The server's state: the last scan's result, the scan running now, and what went wrong with the last one.
///
/// Every tool call goes through this actor. Analysis runs off it, on `BlockingWork`, so calls keep being
/// answered while a scan runs; after each wait the state is read again, since another call may have changed it.
actor MCPSession {
    /// The longest `scan` waits for the scan to finish before answering with its progress.
    static let scanWait = Duration.seconds(5)
    /// How often `scan` checks whether the scan finished while it waits.
    private static let pollInterval = Duration.milliseconds(50)
    /// What a call that needs a result says before any scan has finished.
    private static let noScan = "No scan yet. Call scan first."

    /// What the server was started with.
    let defaults: MCPSessionDefaults
    /// The result calls answer from, once a scan has finished.
    private(set) var snapshot: ResultSnapshot?
    /// The scan running now, if any.
    private(set) var running: ScanProgress?
    /// Why the last scan failed, if it did.
    private(set) var failure: String?
    /// Bumped whenever the result changes, for `orderCache`.
    private var version = 0
    /// The last ordering of every finding a `findings` call cut pages from.
    private var orderCache: (version: Int, grouping: ReportGrouping, findings: [Finding])?
    /// The repo-relative paths of files `verify` re-checked this session, most recent first.
    private(set) var verified: [String] = []

    /// Creates a session with no result yet.
    ///
    /// - Parameter defaults: What the server was started with.
    init(defaults: MCPSessionDefaults) {
        self.defaults = defaults
    }

    /// Starts a scan, unless one is running, and waits a few seconds for it.
    ///
    /// - Parameter options: What the call asked for.
    /// - Returns: The summary if the scan finished in time, otherwise its progress.
    /// - Throws: `ToolError` when the scan can't start.
    func scan(_ options: ScanOptions) async throws -> MCPAnswer {
        if let running { return MCPAnswer(running.line()) }
        let plan = try ScanPlan(options: options, defaults: defaults)
        start(plan)
        let deadline = ContinuousClock.now + Self.scanWait
        while running != nil, ContinuousClock.now < deadline { try? await Task.sleep(for: Self.pollInterval) }
        return try await status()
    }

    /// Answers `status`: a running scan's progress, a failed scan's reason, or the result's summary.
    ///
    /// - Returns: The answer.
    /// - Throws: `ToolError` when the last scan failed or there is no result yet.
    func status() async throws -> MCPAnswer {
        if let running { return MCPAnswer(running.line()) }
        if let failure { throw ToolError("The scan failed: \(failure)") }
        let reading = try await reading()
        return MCPAnswer(lines: reading.header + ToolText.summary(reading.snapshot))
    }

    /// Starts a scan in the background.
    ///
    /// - Parameter plan: The scan.
    private func start(_ plan: ScanPlan) {
        let progress = ScanProgress(log: defaults.log)
        running = progress
        Task {
            let outcome = await BlockingWork.run {
                try plan.scanRunner(onEvent: progress.record).analyzeRecordingFiles()
            }
            finish(outcome, plan: plan, progress: progress)
        }
    }

    /// Keeps a finished scan's result, or why it failed.
    ///
    /// - Parameters:
    ///   - outcome: The recorded run, or the error.
    ///   - plan: The scan.
    ///   - progress: Its progress, for its duration and saved-run note.
    private func finish(_ outcome: Result<RecordedRun, Error>, plan: ScanPlan, progress: ScanProgress) {
        running = nil
        switch outcome {
        case .success(let recorded): keep(recorded, plan: plan, progress: progress)
        case .failure(let error): failure = ToolError.oneLine(error)
        }
        defaults.log.write("scan finished in \(progress.elapsed): \(failure ?? "ok")")
    }

    /// Keeps a finished scan's result, replacing the previous one.
    ///
    /// - Parameters:
    ///   - recorded: The recorded run.
    ///   - plan: The scan.
    ///   - progress: Its progress, for its duration and saved-run note.
    private func keep(_ recorded: RecordedRun, plan: ScanPlan, progress: ScanProgress) {
        let duration = progress.elapsed
        snapshot = ResultSnapshot(recorded: recorded, plan: plan, duration: duration, reuseNote: progress.reuseNote)
        (failure, version) = (nil, version + 1)
    }

    /// The result a reading call answers from, refreshed first under `agent.refresh: immediate`, and the
    /// lines its answer opens with: the result's age, or what the refresh re-checked.
    ///
    /// - Returns: The result and the opening lines.
    /// - Throws: `ToolError` when there is no result yet.
    func reading() async throws -> MCPReading {
        guard let current = snapshot else {
            throw ToolError(running.map { "No scan yet; one is running. \($0.line())" } ?? Self.noScan)
        }
        if let caveat = previousResultCaveat(current) { return MCPReading(current, caveat) }
        guard current.plan.refresh == .immediate else {
            return MCPReading(current, AgentSessionText.ageHeader(seconds: current.ageSeconds))
        }
        return try await refreshed(current)
    }

    /// Says why a call answers from the previous result, when a scan is running or the last one failed.
    ///
    /// - Parameter current: The previous result.
    /// - Returns: The line, or `nil` when the result is the latest scan's.
    private func previousResultCaveat(_ current: ResultSnapshot) -> String? {
        let previous = "answering from the result of \(AgentSessionText.age(seconds: current.ageSeconds))."
        if let running { return "A scan is running (\(running.line())); \(previous)" }
        return failure.map { "The last scan failed (\($0)); \(previous)" }
    }

    /// Re-checks the files that changed since the result was last brought up to date.
    ///
    /// - Parameter current: The result.
    /// - Returns: The refreshed result and a line saying how many files were re-checked.
    /// - Throws: `ToolError` when the changed files can't be analyzed.
    private func refreshed(_ current: ResultSnapshot) async throws -> MCPReading {
        let start = ContinuousClock.now
        let changed = (try? await BlockingWork.run { current.changedFiles() }.get()) ?? []
        defaults.log.write("refresh: stamp check took \(ContinuousClock.now - start), \(changed.count) changed")
        guard !changed.isEmpty else { return MCPReading(current, "Results are current.") }
        _ = try await reanalyze(changed)
        let count = changed.count
        return MCPReading(snapshot ?? current, "Re-checked \(count) changed file\(count == 1 ? "" : "s").")
    }

    /// Re-analyzes some files with the per-file rules and replaces their findings in the result.
    ///
    /// - Parameter urls: The files, which may since have been deleted.
    /// - Returns: The files' findings before and after, and which files were analyzed, removed, or skipped.
    /// - Throws: `ToolError` when there's no result or the files can't be analyzed.
    func reanalyze(_ urls: [URL]) async throws -> Reanalysis {
        guard let plan = snapshot?.plan else { throw ToolError(Self.noScan) }
        let targets = VerifyTargets(urls, plan: plan)
        let before = snapshot?.findings(in: targets.analyzedPaths + targets.removed) ?? []
        let records = try await Self.analyze(targets.analyzed, plan: plan)
        snapshot?.replace(records, analyzed: targets.analyzed, removing: targets.removed)
        version += 1
        return Reanalysis(targets: targets, before: before, after: records.flatMap(\.reported))
    }

    /// Runs the per-file rules over some files, off the actor.
    ///
    /// - Parameters:
    ///   - urls: The files.
    ///   - plan: The scan whose config and walk apply.
    /// - Returns: The files' records.
    /// - Throws: `ToolError` when the analysis fails.
    private static func analyze(_ urls: [URL], plan: ScanPlan) async throws -> [FileRecord] {
        guard !urls.isEmpty else { return [] }
        let files = ScopedFileList(files: urls, walker: plan.walker)
        let outcome = await BlockingWork.run { try plan.runner(files: files).analyzeRecordingFiles().files }
        return try ToolError.wrapping("Can't analyze the files") { try outcome.get() }
    }

    /// Notes files `verify` re-checked, so `next_batch` favors them.
    ///
    /// - Parameter paths: Their repo-relative paths.
    func noteVerified(_ paths: [String]) {
        verified = paths + verified.filter { !paths.contains($0) }
    }

    /// Every finding of a result in the order pages are cut from, reusing the last ordering while the result
    /// hasn't changed.
    ///
    /// - Parameters:
    ///   - snapshot: The result.
    ///   - grouping: The grouping the pages render with.
    /// - Returns: The ordered findings.
    func ordered(_ snapshot: ResultSnapshot, grouping: ReportGrouping) -> [Finding] {
        if let orderCache, orderCache.version == version, orderCache.grouping == grouping { return orderCache.findings }
        let findings = AgentPager(repoRoot: defaults.repoRoot, grouping: grouping).ordered(snapshot.result.findings)
        orderCache = (version, grouping, findings)
        return findings
    }
}

/// A result to answer from, and the lines that open the answer.
struct MCPReading: Sendable {
    /// The result.
    let snapshot: ResultSnapshot
    /// The opening lines.
    let header: [String]

    /// Pairs a result with one opening line.
    ///
    /// - Parameters:
    ///   - snapshot: The result.
    ///   - line: The opening line.
    init(_ snapshot: ResultSnapshot, _ line: String) {
        (self.snapshot, header) = (snapshot, [line])
    }
}

/// A tool's answer text, before it's wrapped in a tool result.
struct MCPAnswer: Sendable {
    /// The text.
    let text: String

    /// Wraps one line or block of text.
    ///
    /// - Parameter text: The text.
    init(_ text: String) {
        self.text = text
    }

    /// Joins lines.
    ///
    /// - Parameter lines: The lines.
    init(lines: [String]) {
        text = lines.joined(separator: "\n")
    }
}
