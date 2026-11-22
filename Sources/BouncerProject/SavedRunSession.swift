import Foundation
import BouncerCore

/// What a `review` does with the saved last run.
public enum SavedRunMode: Sendable, Equatable {
    /// Start from the saved run, then save this one: the default, and `--from-last-run`.
    case incremental
    /// Analyze every file, then save this run: `--full`.
    case full
    /// Start from the saved run without saving this one: `--from-last-run` with saving turned off.
    case readOnly

    /// Whether the run starts from the saved run.
    public var reads: Bool { self != .full }
    /// Whether the run saves its result.
    public var saves: Bool { self != .readOnly }
}

/// A `review`'s saved last run: loading it to start from, and saving this run's result.
public struct SavedRunSession: Sendable {
    /// Where the saved run lives.
    public let store: JSONSavedRunStore
    /// The key this run's result is saved under, and that a saved run must match to be reused.
    public let key: SavedRun.Key
    /// What the run does with the saved run.
    public let mode: SavedRunMode

    /// Creates a session.
    ///
    /// - Parameters:
    ///   - store: Where the saved run lives.
    ///   - key: This run's key.
    ///   - mode: What the run does with the saved run.
    public init(store: JSONSavedRunStore, key: SavedRun.Key, mode: SavedRunMode) {
        self.store = store
        self.key = key
        self.mode = mode
    }

    /// Loads the saved run to start from, or a stand-in saying why it can't be used.
    ///
    /// - Returns: The prior run, or `nil` when this run doesn't read one.
    public func prior() -> PriorRun? {
        guard mode.reads else { return nil }
        do {
            return try loadPrior()
        } catch {
            return UnusableSavedRun(reason: "the saved run can't be read: \(error)")
        }
    }

    /// Loads the saved run and checks its key.
    ///
    /// - Returns: The saved run to reuse, or a stand-in saying why it can't be used.
    /// - Throws: If the saved run can't be read or decoded.
    private func loadPrior() throws -> PriorRun {
        guard let run = try store.load() else { return UnusableSavedRun(reason: "there is no saved run yet") }
        if let mismatch = run.key.mismatch(with: key) { return UnusableSavedRun(reason: mismatch) }
        return SavedRunReuse(run)
    }

    /// Saves a run's result, noting where it went or why it couldn't be saved; a failure never fails the run.
    ///
    /// - Parameters:
    ///   - recorded: The run.
    ///   - repoRoot: The repository root.
    ///   - emit: Receives the note.
    public func save(_ recorded: RecordedRun, repoRoot: URL, emit: AnalysisEventHandler) {
        guard mode.saves else { return }
        let run = SavedRun(key: key, recorded: recorded, repoRoot: repoRoot)
        do {
            let bytes = try store.save(run)
            emit(.note("saved this run to \(store.location.path) (\(run.reportedCount) finding(s), \(bytes) bytes)"))
        } catch {
            emit(.note("couldn't save this run to \(store.location.path): \(error)"))
        }
    }
}

extension SavedRun.Key {
    /// Builds a key from a build identity, a config, and the reviewed directory.
    ///
    /// - Parameters:
    ///   - version: The Bouncer build.
    ///   - config: The fully merged config, profile included; it's hashed from its JSON with sorted keys.
    ///   - root: The reviewed directory.
    public init<Config: Encodable>(version: String, config: Config, root: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = (try? encoder.encode(config)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        self.init(version: version, config: StableHash.hex(json), root: root.standardizedFileURL.path)
    }

    /// Says why a saved run's key doesn't match this run's.
    ///
    /// - Parameter current: This run's key.
    /// - Returns: The reason, or `nil` if the keys match.
    public func mismatch(with current: SavedRun.Key) -> String? {
        if version != current.version { return "it was made by another Bouncer build" }
        if config != current.config { return "the config changed since it was saved" }
        if root != current.root { return "it reviewed \(root)" }
        return nil
    }
}
