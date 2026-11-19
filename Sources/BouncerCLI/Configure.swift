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

    @Option(parsing: .upToNextOption, help: "A dotted.path=value edit, repeatable. Skips the interactive walkthrough.")
    var set: [String] = []

    @Flag(help: "Append a line invoking 'bouncer check' to .husky/pre-commit.")
    var husky = false

    @Flag(help: "Trust the current repo's declared hooks without the interactive prompt.")
    var trust = false

    /// Applies the requested edit, wiring, or trust action.
    ///
    /// - Throws: If the target file can't be read, parsed, or written.
    func run() async throws {
        let path = try targetPath()
        if trust { try trustCurrentRepoHooks(); return }
        if husky { try wireHusky(); return }
        if !set.isEmpty { try applySets(to: path); return }
        try runInteractiveWalkthrough(at: path)
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
        var json = try readJSONObject(at: path)
        for edit in set { json = try apply(edit, to: json) }
        try write(json, to: path)
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

    /// Runs a short interactive prompt for the most common settings.
    ///
    /// - Parameter path: The `.bouncer` file to write.
    /// - Throws: If the existing file can't be parsed, or the result can't be written.
    private func runInteractiveWalkthrough(at path: URL) throws {
        var json = try readJSONObject(at: path)
        json = promptOutputVerbosity(into: json)
        json = promptCoverage(into: json)
        try write(json, to: path)
        print("Wrote \(path.path).")
    }

    /// Prompts for `output.verbosity`, leaving the existing value if the answer is blank.
    ///
    /// - Parameter json: The JSON object to update.
    /// - Returns: The updated object.
    private func promptOutputVerbosity(into json: [String: Any]) -> [String: Any] {
        print("Default output verbosity [normal/verbose/quiet/condensed]: ", terminator: "")
        guard let answer = readLine(), !answer.isEmpty else { return json }
        return DottedPathJSON.apply(path: "output.verbosity", value: answer, to: json)
    }

    /// Prompts for coverage settings, leaving existing values if the answers are blank.
    ///
    /// - Parameter json: The JSON object to update.
    /// - Returns: The updated object.
    private func promptCoverage(into json: [String: Any]) -> [String: Any] {
        print("Enable coverage checking? [y/N]: ", terminator: "")
        guard readLine()?.lowercased().hasPrefix("y") == true else { return json }
        var json = DottedPathJSON.apply(path: "coverage.enabled", value: "true", to: json)
        json = promptCoverageReportPath(into: json)
        return promptCoverageThreshold(into: json)
    }

    /// Prompts for the coverage report's path, leaving the existing value if the answer is blank.
    ///
    /// - Parameter json: The JSON object to update.
    /// - Returns: The updated object.
    private func promptCoverageReportPath(into json: [String: Any]) -> [String: Any] {
        print("Coverage report path: ", terminator: "")
        guard let reportPath = readLine(), !reportPath.isEmpty else { return json }
        return DottedPathJSON.apply(path: "coverage.reportPath", value: reportPath, to: json)
    }

    /// Prompts for the coverage threshold, defaulting to 80 if the answer is blank.
    ///
    /// - Parameter json: The JSON object to update.
    /// - Returns: The updated object.
    private func promptCoverageThreshold(into json: [String: Any]) -> [String: Any] {
        print("Coverage threshold percentage [80]: ", terminator: "")
        let threshold = readLine().flatMap { $0.isEmpty ? nil : $0 } ?? "80"
        return DottedPathJSON.apply(path: "coverage.threshold", value: threshold, to: json)
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
    /// - Throws: If the repo's `.bouncer` can't be read, or the trust store can't be written.
    private func trustCurrentRepoHooks() throws {
        let repoRoot = try repoRootOrCurrentDirectory()
        let resolution = try ConfigResolver.resolve(repoRoot: repoRoot, profile: nil, explicitPath: nil)
        guard let hooks = resolution.rawRepo.hooks else { print("This repo's .bouncer declares no hooks."); return }
        let hash = TrustStore.contentHash(of: hooks)
        try TrustStore(path: BouncerPaths.trustStore).trust(repoPath: repoRoot.path, hooksHash: hash)
        print("Trusted the hooks in \(repoRoot.path)/.bouncer.")
    }

    /// Reads a `.bouncer` file as a JSON object, or an empty object if it doesn't exist.
    ///
    /// - Parameter path: The file to read.
    /// - Returns: The decoded JSON object.
    /// - Throws: If the file exists but isn't a valid JSON object.
    private func readJSONObject(at path: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: path) else { return [:] }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Writes a JSON object to a file as pretty-printed, sorted JSON.
    ///
    /// - Parameters:
    ///   - json: The object to write.
    ///   - path: The destination file.
    /// - Throws: If the object can't be serialized or the file can't be written.
    private func write(_ json: [String: Any], to path: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: path)
    }

    /// Finds the current git repo's root, or falls back to the current directory.
    ///
    /// - Returns: The repository root, or the current directory outside a repo.
    private func repoRootOrCurrentDirectory() throws -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return GitRepoLocator.repoRoot(startingAt: cwd) ?? cwd
    }
}
