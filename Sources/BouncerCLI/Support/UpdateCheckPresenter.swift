import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import BouncerConfig
import BouncerUpdateCheck

/// Runs the pre-flight update check and presents its result appropriately for the context.
enum UpdateCheckPresenter {
    /// Checks for an update and prints a message if one is available.
    ///
    /// - Parameters:
    ///   - config: The merged `.bouncer` `updateCheck` section.
    ///   - noUpdateCheckFlag: Whether `--no-update-check` was passed.
    ///   - isAgentInvocation: Whether this run used an agent-facing flag (`--files`, `--stdin`).
    ///   - format: The requested output format.
    static func run(
        config: UpdateCheckConfig?, noUpdateCheckFlag: Bool, isAgentInvocation: Bool, format: OutputFormat
    ) async {
        guard shouldRun(config: config, flag: noUpdateCheckFlag) else { return }
        let checker = makeChecker(config: config)
        let result = await checker.check()
        guard result.updateAvailable, let tag = result.latestTag else { return }
        present(tag: tag, interactive: isInteractiveContext(isAgentInvocation: isAgentInvocation, format: format))
    }

    /// Builds the update checker for the configured (or default) repository.
    ///
    /// - Parameter config: The merged `.bouncer` `updateCheck` section.
    /// - Returns: A checker ready to run.
    private static func makeChecker(config: UpdateCheckConfig?) -> UpdateChecker {
        UpdateChecker(
            lookup: URLSessionGitHubReleaseLookup(),
            cachePath: BouncerPaths.updateCheckCache,
            currentSHA: GeneratedVersion.commitSHA,
            repo: config?.repo ?? "matthewayers/bouncer",
            intervalHours: config?.intervalHours ?? 24
        )
    }

    /// Decides whether the update check should run at all.
    ///
    /// - Parameters:
    ///   - config: The merged `.bouncer` `updateCheck` section.
    ///   - flag: Whether `--no-update-check` was passed.
    /// - Returns: Whether the check should run.
    private static func shouldRun(config: UpdateCheckConfig?, flag: Bool) -> Bool {
        guard !flag, config?.enabled != false else { return false }
        return ProcessInfo.processInfo.environment["BOUNCER_NO_UPDATE_CHECK"] == nil
    }

    /// Decides whether a human is likely present to answer a blocking prompt.
    ///
    /// - Parameters:
    ///   - isAgentInvocation: Whether this run used an agent-facing flag.
    ///   - format: The requested output format.
    /// - Returns: Whether it's safe to print an interactive notice.
    private static func isInteractiveContext(isAgentInvocation: Bool, format: OutputFormat) -> Bool {
        let isCI = ProcessInfo.processInfo.environment["CI"] != nil
        guard !isAgentInvocation, format == .console, !isCI else { return false }
        return isatty(FileHandle.standardOutput.fileDescriptor) != 0
    }

    /// Prints the update notice, to stdout when interactive, otherwise to stderr.
    ///
    /// - Parameters:
    ///   - tag: The latest available release's tag.
    ///   - interactive: Whether a human is likely watching.
    private static func present(tag: String, interactive: Bool) {
        let message = "A newer bouncer release is available: \(tag). Run 'brew upgrade bouncer' to update."
        guard interactive else {
            FileHandle.standardError.write(Data((message + "\n").utf8))
            return
        }
        print(message)
    }
}
