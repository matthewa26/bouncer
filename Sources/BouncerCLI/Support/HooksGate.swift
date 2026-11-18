import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import BouncerConfig

/// Decides which hooks are safe to run, gating any repo-declared ones behind trust.
///
/// A repo-committed `.bouncer` can declare shell commands that would
/// otherwise auto-execute the moment anyone runs `bouncer check`/`review`
/// against a freshly cloned copy. This mirrors direnv's `.envrc` allow-list.
enum HooksGate {
    /// Resolves which hooks are allowed to run for this invocation.
    ///
    /// - Parameters:
    ///   - repoConfig: The repo's own, unmerged `.bouncer` contents.
    ///   - globalHooks: The hooks declared in `~/.bouncer`, always trusted.
    ///   - mergedHooks: The fully merged hooks (global concatenated with repo).
    ///   - repoRoot: The repository root, used as the trust key.
    ///   - allowHooksFlag: Whether `--allow-hooks` was passed, bypassing the prompt.
    /// - Returns: The hooks that are safe to run this invocation.
    static func resolve(
        repoConfig: BouncerConfig, globalHooks: HooksConfig?, mergedHooks: HooksConfig?,
        repoRoot: URL, allowHooksFlag: Bool
    ) -> HooksConfig? {
        guard let repoHooks = repoConfig.hooks, !isEmpty(repoHooks) else { return mergedHooks }
        let store = TrustStore(path: BouncerPaths.trustStore)
        let hash = TrustStore.contentHash(of: repoHooks)
        if allowHooksFlag || store.isTrusted(repoPath: repoRoot.path, hooksHash: hash) { return mergedHooks }
        return promptOrSkip(
            repoHooks: repoHooks, store: store, hash: hash, repoRoot: repoRoot,
            fallback: globalHooks, mergedHooks: mergedHooks
        )
    }

    /// Prompts interactively for trust, or skips the repo's hooks in a non-interactive context.
    ///
    /// - Parameters:
    ///   - repoHooks: The repo-declared hooks being gated.
    ///   - store: The trust store to record a positive answer into.
    ///   - hash: The content hash to trust.
    ///   - repoRoot: The repository root.
    ///   - fallback: The hooks to use if trust is declined, typically the global-only hooks.
    ///   - mergedHooks: The hooks to use if trust is granted.
    /// - Returns: `mergedHooks` if trusted, otherwise `fallback`.
    private static func promptOrSkip(
        repoHooks: HooksConfig, store: TrustStore, hash: String, repoRoot: URL,
        fallback: HooksConfig?, mergedHooks: HooksConfig?
    ) -> HooksConfig? {
        guard isInteractive(), confirm(repoHooks: repoHooks) else {
            warn("bouncer: skipping untrusted hooks in \(repoRoot.path)/.bouncer (run 'bouncer configure --trust').")
            return fallback
        }
        try? store.trust(repoPath: repoRoot.path, hooksHash: hash)
        return mergedHooks
    }

    /// Prints the repo's declared hooks and asks the user to confirm running them.
    ///
    /// - Parameter repoHooks: The hooks to display.
    /// - Returns: Whether the user answered yes.
    private static func confirm(repoHooks: HooksConfig) -> Bool {
        print("This repository's .bouncer declares hooks:")
        (repoHooks.preCheck ?? []).forEach { print("  preCheck: \($0)") }
        (repoHooks.postCheck ?? []).forEach { print("  postCheck: \($0)") }
        print("Trust and run them? [y/N]: ", terminator: "")
        return readLine()?.lowercased().hasPrefix("y") == true
    }

    /// Reports whether standard input is an interactive terminal.
    ///
    /// - Returns: Whether a human is likely present to answer a prompt.
    private static func isInteractive() -> Bool {
        Terminal.standardInputIsInteractive
    }

    /// Reports whether a hooks config has no commands in either phase.
    ///
    /// - Parameter hooks: The hooks config to check.
    /// - Returns: Whether both `preCheck` and `postCheck` are empty or absent.
    private static func isEmpty(_ hooks: HooksConfig) -> Bool {
        (hooks.preCheck ?? []).isEmpty && (hooks.postCheck ?? []).isEmpty
    }

    /// Writes a message to standard error.
    ///
    /// - Parameter message: The message to write.
    private static func warn(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
