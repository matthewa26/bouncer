import ArgumentParser
import Foundation
import BouncerConfig
import BouncerGit

/// Lists, shows, creates, selects, and deletes named config profiles.
///
/// A profile is a `.bouncer`-schema file in `<repoRoot>/.bouncer-profiles/` or `~/.bouncer-profiles/`, or a
/// bundled preset such as `kirby`. It's applied beneath `~/.bouncer` and the repo's `.bouncer`.
struct ProfileCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "profile", abstract: "Manage named config profiles.",
        subcommands: [List.self, Show.self, Create.self, SetDefault.self, Delete.self]
    )

    /// The help text for every subcommand's profile-name argument.
    static let nameHelp: ArgumentHelp = "The profile's name."

    /// Finds the current git repo's root, or falls back to the current directory.
    ///
    /// - Returns: The repository root, or the current directory outside a repo.
    static func repoRoot() -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return GitRepoLocator.repoRoot(startingAt: cwd) ?? cwd
    }

    /// The profile the repo and global `.bouncer` files select, ignoring any `--profile` flag.
    ///
    /// - Parameter repoRoot: The repository root.
    /// - Returns: The repo's `"profile"`, else the global one's, else `nil`.
    /// - Throws: If either file exists but isn't valid JSON.
    static func defaultProfileName(repoRoot: URL) throws -> String? {
        let loader = ConfigLoader()
        let repo = try loader.read(BouncerPaths.repoConfig(repoRoot: repoRoot))
        let files = [repo, try loader.read(BouncerPaths.globalConfig)]
        return ConfigLoader.effectiveProfileName(cli: nil, files: files)
    }
}

extension ProfileCommand {
    /// Prints every profile, its source, and which one is the effective default.
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List profiles; * marks the default.")

        /// Prints one row per profile.
        ///
        /// - Throws: If a `.bouncer` file exists but isn't valid JSON.
        func run() throws {
            let repoRoot = ProfileCommand.repoRoot()
            let listings = BouncerPaths.profileStore(repoRoot: repoRoot).list()
            let current = try ProfileCommand.defaultProfileName(repoRoot: repoRoot)
            rows(listings, current: current).forEach { print($0) }
            if let current, !listings.contains(where: { $0.name == current }) {
                print("warning: the default profile \"\(current)\" doesn't exist.")
            }
        }

        /// Formats every listing, marking the default and any copy a higher-precedence one shadows.
        ///
        /// - Parameters:
        ///   - listings: The profiles, in precedence order.
        ///   - current: The effective default profile's name.
        /// - Returns: Rows such as `* kirby  bundled`.
        private func rows(_ listings: [ProfileListing], current: String?) -> [String] {
            let width = listings.map(\.name.count).max() ?? 0
            var seen = Set<String>()
            return listings.map { listing in
                let shadowed = !seen.insert(listing.name).inserted
                let marker = listing.name == current && !shadowed ? "*" : " "
                let name = listing.name.padding(toLength: width, withPad: " ", startingAt: 0)
                return "\(marker) \(name)  \(listing.source.rawValue)\(shadowed ? " (shadowed)" : "")"
            }
        }
    }

    /// Prints one profile's contents as JSON.
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print a profile as JSON.")

        @Argument(help: ProfileCommand.nameHelp)
        var name: String

        /// Prints the profile.
        ///
        /// - Throws: A `ProfileError` if it's missing or invalid, or an encoding error.
        func run() throws {
            let config = try BouncerPaths.profileStore(repoRoot: ProfileCommand.repoRoot()).config(named: name)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(data: try encoder.encode(config), encoding: .utf8) ?? "{}")
        }
    }

    /// Makes a profile the default by writing `"profile"` into the repo's or the global `.bouncer`.
    struct SetDefault: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-default", abstract: "Select a profile in .bouncer (or ~/.bouncer with --global)."
        )

        @Argument(help: ProfileCommand.nameHelp)
        var name: String

        @Flag(help: "Write ~/.bouncer instead of the repo's .bouncer.")
        var global = false

        /// Validates the profile and writes the pointer.
        ///
        /// A global default can only name a global or bundled profile, since other repos can't see repo ones.
        ///
        /// - Throws: A `ProfileError` if the profile can't be found from that scope, or a file error.
        func run() throws {
            let repoRoot = ProfileCommand.repoRoot()
            let sources: [ProfileSource] = global ? [.global, .bundled] : ProfileSource.allCases
            _ = try BouncerPaths.profileStore(repoRoot: repoRoot).locate(name, in: sources)
            let path = global ? BouncerPaths.globalConfig : BouncerPaths.repoConfig(repoRoot: repoRoot)
            let existing = try ConfigFileJSON.readObject(at: path)
            try ConfigFileJSON.write(DottedPathJSON.applyString(path: "profile", value: name, to: existing), to: path)
            print("Set the default profile to \"\(name)\" in \(path.path).")
        }
    }
}
