import ArgumentParser
import Foundation
import BouncerConfig

extension ProfileCommand {
    /// Creates a profile file by running the setup wizard with the profile as its save target.
    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a profile with the setup wizard.")

        @Argument(help: ProfileCommand.nameHelp)
        var name: String

        @Flag(help: "Create it in ~/.bouncer-profiles instead of the repo's .bouncer-profiles.")
        var global = false

        /// Runs the wizard.
        ///
        /// - Throws: `ValidationError` without a terminal or if the profile exists, or a wizard error.
        func run() throws {
            guard Terminal.standardInputIsInteractive else {
                throw ValidationError("Creating a profile runs the setup wizard, which needs an interactive terminal.")
            }
            let repoRoot = ProfileCommand.repoRoot()
            try ensureAbsent(store: BouncerPaths.profileStore(repoRoot: repoRoot))
            let wizard = SetupWizard(prompt: .standard, paths: BouncerPaths.setupPaths(repoRoot: repoRoot))
            _ = try wizard.run(target: .profile(name: name, scope: global ? .global : .repo))
        }

        /// Refuses to overwrite an existing profile file.
        ///
        /// - Parameter store: The profile store.
        /// - Throws: `ProfileError.invalidName`, or `ValidationError` if the file already exists.
        private func ensureAbsent(store: ProfileStore) throws {
            let path = try store.fileURL(for: name, in: global ? .global : .repo)
            guard let path, FileManager.default.fileExists(atPath: path.path) else { return }
            throw ValidationError("\(path.path) already exists. Edit it, or delete it first.")
        }
    }

    /// Deletes a repo or global profile file, after confirming.
    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a repo (or --global) profile file.")

        @Argument(help: ProfileCommand.nameHelp)
        var name: String

        @Flag(help: "Delete from ~/.bouncer-profiles instead of the repo's .bouncer-profiles.")
        var global = false

        @Flag(help: "Delete without asking for confirmation.")
        var yes = false

        /// Confirms and deletes the file.
        ///
        /// - Throws: A `ProfileError` for a bundled or invalid name, `ValidationError` if it's missing or
        ///   unconfirmable, or a file error.
        func run() throws {
            let repoRoot = ProfileCommand.repoRoot()
            let path = try existingFile(store: BouncerPaths.profileStore(repoRoot: repoRoot))
            guard try confirmed(path) else { print("Kept \(path.path)."); return }
            try FileManager.default.removeItem(at: path)
            print("Deleted \(path.path).")
            if try ProfileCommand.defaultProfileName(repoRoot: repoRoot) == name {
                print("warning: \"\(name)\" is still selected as a default profile; run 'bouncer profile set-default'.")
            }
        }

        /// Finds the profile file this invocation would delete.
        ///
        /// - Parameter store: The profile store.
        /// - Returns: The existing file.
        /// - Throws: `ProfileError.bundled` for a bundled-only name, or `ValidationError` if it doesn't exist.
        private func existingFile(store: ProfileStore) throws -> URL {
            let source: ProfileSource = global ? .global : .repo
            let path = try store.fileURL(for: name, in: source)
            if let path, FileManager.default.fileExists(atPath: path.path) { return path }
            if BundledProfiles.config(named: name) != nil { throw ProfileError.bundled(name) }
            throw ValidationError("No \(source.rawValue) profile named \"\(name)\" (\(path?.path ?? "no directory")).")
        }

        /// Asks before deleting, unless `--yes` was passed.
        ///
        /// - Parameter path: The file about to be deleted.
        /// - Returns: Whether to delete it.
        /// - Throws: `ValidationError` without a terminal or `--yes`, or `PromptError.endOfInput`.
        private func confirmed(_ path: URL) throws -> Bool {
            if yes { return true }
            guard Terminal.standardInputIsInteractive else {
                throw ValidationError("Refusing to delete \(path.path) without confirmation; pass --yes.")
            }
            return try Prompt.standard.yesNo("Delete \(path.path)?", default: false)
        }
    }
}
