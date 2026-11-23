import Foundation
import BouncerCore
import BouncerConfig
import BouncerProject

extension SavedRunSession {
    /// Works out what a `review` invocation does with its saved run.
    ///
    /// - Parameters:
    ///   - arguments: The `--from-last-run`, `--full`, and `--no-save-run` flags.
    ///   - config: The merged config, for `output.saveRun` and the key's config hash.
    ///   - rootDirectory: The reviewed directory.
    ///   - repoRoot: The repository root, where `.bouncer-cache/` lives.
    /// - Returns: The session, or `nil` when the run neither reads nor saves a saved run.
    static func make(
        arguments: SavedRunArguments, config: BouncerConfig, rootDirectory: URL, repoRoot: URL
    ) -> SavedRunSession? {
        let flags = (fromLastRun: arguments.fromLastRun, full: arguments.full, noSaveRun: arguments.noSaveRun)
        guard let mode = mode(flags, config: config) else { return nil }
        return make(mode: mode, config: config, rootDirectory: rootDirectory, repoRoot: repoRoot)
    }

    /// Works out what a `bouncer mcp` scan does with its saved run: start from it and save over it (`.incremental`),
    /// or only save over it (`.full`); with `output.saveRun` off, start from it without saving, or neither.
    ///
    /// - Parameters:
    ///   - scan: `.incremental`, or `.full` to ignore the saved run.
    ///   - config: The merged config, for `output.saveRun` and the key's config hash.
    ///   - rootDirectory: The scanned directory.
    ///   - repoRoot: The repository root, where `.bouncer-cache/` lives.
    /// - Returns: The session, or `nil` when the scan neither reads nor saves a saved run.
    static func make(scan: SavedRunMode, config: BouncerConfig, rootDirectory: URL, repoRoot: URL) -> SavedRunSession? {
        let full = scan == .full
        guard let mode = mode((fromLastRun: !full, full: full, noSaveRun: false), config: config) else { return nil }
        return make(mode: mode, config: config, rootDirectory: rootDirectory, repoRoot: repoRoot)
    }

    /// Builds a session for a mode. The key hashes the config without its `agent` section, which only changes
    /// how a long-lived session refreshes, so editing it never discards the saved findings.
    ///
    /// - Parameters:
    ///   - mode: What the run does with the saved run.
    ///   - config: The merged config.
    ///   - rootDirectory: The reviewed directory.
    ///   - repoRoot: The repository root.
    /// - Returns: The session.
    private static func make(
        mode: SavedRunMode, config: BouncerConfig, rootDirectory: URL, repoRoot: URL
    ) -> SavedRunSession {
        var keyed = config
        keyed.agent = nil
        let key = SavedRun.Key(version: buildIdentity, config: keyed, root: rootDirectory)
        return SavedRunSession(store: JSONSavedRunStore(repoRoot: repoRoot), key: key, mode: mode)
    }

    /// Maps the flags and `output.saveRun` to a mode.
    ///
    /// - Parameters:
    ///   - flags: The `--from-last-run`, `--full`, and `--no-save-run` flags.
    ///   - config: The merged config.
    /// - Returns: The mode, or `nil` when saving is off and `--from-last-run` isn't given.
    private static func mode(
        _ flags: (fromLastRun: Bool, full: Bool, noSaveRun: Bool), config: BouncerConfig
    ) -> SavedRunMode? {
        let saving = !flags.noSaveRun && config.output?.saveRun != false
        if flags.fromLastRun { return saving ? .incremental : .readOnly }
        guard saving else { return nil }
        return flags.full ? .full : .incremental
    }

    /// This build: its version and commit, and its executable's size and modification time, so a rebuilt
    /// development binary with the same placeholder version never reuses an older build's findings.
    private static var buildIdentity: String {
        let binary = Bundle.main.executableURL.flatMap(FileStamp.read)
        let stamp = binary.map { "\($0.size)-\($0.modified)" } ?? "unknown"
        return "\(GeneratedVersion.versionString) \(GeneratedVersion.commitSHA) \(stamp)"
    }
}
