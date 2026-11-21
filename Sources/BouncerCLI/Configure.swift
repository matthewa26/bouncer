import ArgumentParser
import Foundation
import BouncerConfig
import BouncerGit

/// Creates or edits a `.bouncer` file, globally or for the current repo.
struct Configure: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "configure", abstract: "Create or edit a .bouncer file."
    )

    @Flag(help: "Edit ~/.bouncer instead of the current repo's .bouncer.")
    var global = false

    @Option(parsing: .upToNextOption, help: "A dotted.path=value edit, repeatable. Skips the setup wizard.")
    var set: [String] = []

    @Flag(help: "Append a line invoking 'bouncer check' to .husky/pre-commit.")
    var husky = false

    @Flag(help: "Trust the current repo's declared hooks without the interactive prompt.")
    var trust = false

    /// Applies the requested edit, wiring, or trust action, or runs the setup wizard when none is given.
    ///
    /// - Throws: If the target file can't be read, parsed, or written.
    func run() async throws {
        let path = try targetPath()
        if trust { try trustCurrentRepoHooks(); return }
        if husky { try wireHusky(); return }
        if !set.isEmpty { try applySets(to: path); return }
        try runSetupWizard()
    }

    /// Resolves which `.bouncer` file this invocation edits.
    ///
    /// - Returns: `~/.bouncer` if `--global`, otherwise the current repo's `.bouncer`.
    /// - Throws: If the current directory can't be resolved.
    private func targetPath() throws -> URL {
        global ? BouncerPaths.globalConfig : BouncerPaths.repoConfig(repoRoot: try repoRootOrCurrentDirectory())
    }

    /// Applies every `--set` edit to the target file's JSON.
    ///
    /// - Parameter path: The `.bouncer` file to edit.
    /// - Throws: If the existing file can't be parsed, or the result can't be written.
    private func applySets(to path: URL) throws {
        var json = try ConfigFileJSON.readObject(at: path)
        for edit in set { json = try apply(edit, to: json) }
        try ConfigFileJSON.write(json, to: path)
        print("Updated \(path.path).")
    }

    /// Parses one `key.path=value` edit and applies it to a JSON object.
    ///
    /// - Parameters:
    ///   - edit: The raw `--set` argument.
    ///   - json: The JSON object to update.
    /// - Returns: The updated object.
    /// - Throws: `ValidationError` if `edit` isn't in `key=value` form.
    private func apply(_ edit: String, to json: [String: Any]) throws -> [String: Any] {
        guard let separator = edit.firstIndex(of: "=") else {
            throw ValidationError("Expected key.path=value, got \"\(edit)\".")
        }
        let key = String(edit[edit.startIndex..<separator])
        let value = String(edit[edit.index(after: separator)...])
        return DottedPathJSON.apply(path: key, value: value, to: json)
    }

    /// Runs the setup wizard, which needs a human at a terminal to answer it.
    ///
    /// `--global` makes `~/.bouncer` the save target's default answer.
    ///
    /// - Throws: `ValidationError` when standard input isn't a terminal, or a wizard error.
    private func runSetupWizard() throws {
        guard Terminal.standardInputIsInteractive else {
            throw ValidationError(
                "The setup wizard needs an interactive terminal. Non-interactively, use 'bouncer configure "
                    + "--set dotted.path=value', such as --set rules.long-function.params.maxLines=25."
            )
        }
        let paths = BouncerPaths.setupPaths(repoRoot: try repoRootOrCurrentDirectory())
        _ = try SetupWizard(prompt: .standard, paths: paths).run(preferredScope: global ? .global : .repo)
    }

    /// Appends a `bouncer check` line to `.husky/pre-commit`.
    ///
    /// - Throws: If `.husky` doesn't already exist, or the file can't be written.
    private func wireHusky() throws {
        let huskyDir = try repoRootOrCurrentDirectory().appendingPathComponent(".husky")
        guard FileManager.default.fileExists(atPath: huskyDir.path) else {
            print("No .husky directory found. Run 'npx husky init' first, then re-run 'bouncer configure --husky'.")
            return
        }
        try appendHuskyLine(in: huskyDir)
    }

    /// Appends or creates `.husky/pre-commit` with a line invoking `bouncer check`.
    ///
    /// - Parameter huskyDir: The `.husky` directory.
    /// - Throws: If the file can't be read or written.
    private func appendHuskyLine(in huskyDir: URL) throws {
        let hookPath = huskyDir.appendingPathComponent("pre-commit")
        let existing = (try? String(contentsOf: hookPath, encoding: .utf8)) ?? "#!/usr/bin/env sh\n"
        guard !existing.contains("bouncer check") else {
            print("bouncer check is already wired into .husky/pre-commit.")
            return
        }
        try (existing + "bouncer check\n").write(to: hookPath, atomically: true, encoding: .utf8)
        print("Added 'bouncer check' to .husky/pre-commit.")
    }

    /// Records the current repo's declared hooks as trusted.
    ///
    /// Reads only the repo's own `.bouncer`, so a broken profile reference elsewhere can't block trusting.
    ///
    /// - Throws: If the repo's `.bouncer` can't be read, or the trust store can't be written.
    private func trustCurrentRepoHooks() throws {
        let repoRoot = try repoRootOrCurrentDirectory()
        let rawRepo = try ConfigLoader().read(BouncerPaths.repoConfig(repoRoot: repoRoot))
        guard let hooks = rawRepo.hooks else { print("This repo's .bouncer declares no hooks."); return }
        let hash = TrustStore.contentHash(of: hooks)
        try TrustStore(path: BouncerPaths.trustStore).trust(repoPath: repoRoot.path, hooksHash: hash)
        print("Trusted the hooks in \(repoRoot.path)/.bouncer.")
    }

    /// Finds the current git repo's root, or falls back to the current directory.
    ///
    /// - Returns: The repository root, or the current directory outside a repo.
    private func repoRootOrCurrentDirectory() throws -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return GitRepoLocator.repoRoot(startingAt: cwd) ?? cwd
    }
}
