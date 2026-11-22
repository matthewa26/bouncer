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
        guard let mode = mode(arguments: arguments, config: config) else { return nil }
        let key = SavedRun.Key(version: buildIdentity, config: config, root: rootDirectory)
        return SavedRunSession(store: JSONSavedRunStore(repoRoot: repoRoot), key: key, mode: mode)
    }

    /// Maps the flags and `output.saveRun` to a mode.
    ///
    /// - Parameters:
    ///   - arguments: The flags.
    ///   - config: The merged config.
    /// - Returns: The mode, or `nil` when saving is off and `--from-last-run` isn't given.
    private static func mode(arguments: SavedRunArguments, config: BouncerConfig) -> SavedRunMode? {
        let saving = !arguments.noSaveRun && config.output?.saveRun != false
        if arguments.fromLastRun { return saving ? .incremental : .readOnly }
        guard saving else { return nil }
        return arguments.full ? .full : .incremental
    }

    /// This build: its version and commit, and its executable's size and modification time, so a rebuilt
    /// development binary with the same placeholder version never reuses an older build's findings.
    private static var buildIdentity: String {
        let binary = Bundle.main.executableURL.flatMap(FileStamp.read)
        let stamp = binary.map { "\($0.size)-\($0.modified)" } ?? "unknown"
        return "\(GeneratedVersion.versionString) \(GeneratedVersion.commitSHA) \(stamp)"
    }
}
