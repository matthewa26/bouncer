import Foundation

/// Which side of the repo/user split a wizard write lands on.
public enum SetupScope: String, Sendable, Equatable {
    /// The current repo: `.bouncer` or `.bouncer-profiles/`.
    case repo
    /// The current user: `~/.bouncer` or `~/.bouncer-profiles/`.
    case global

    /// The profile source this scope's profile files belong to.
    var profileSource: ProfileSource { self == .repo ? .repo : .global }
}

/// Where the setup wizard saves its answers.
public enum SetupTarget: Sendable, Equatable {
    /// A `.bouncer` file: the repo's, or `~/.bouncer`.
    case config(SetupScope)
    /// A named profile file under the repo's or the user's `.bouncer-profiles/`.
    case profile(name: String, scope: SetupScope)
}

/// The files the setup wizard reads from and writes to.
public struct SetupPaths {
    /// `<repoRoot>/.bouncer`.
    public let repoConfig: URL
    /// `~/.bouncer`.
    public let globalConfig: URL
    /// The named-profile store, for starting points and profile targets.
    public let store: ProfileStore

    /// Creates the wizard's file locations.
    ///
    /// - Parameters:
    ///   - repoConfig: `<repoRoot>/.bouncer`.
    ///   - globalConfig: `~/.bouncer`.
    ///   - store: The named-profile store.
    public init(repoConfig: URL, globalConfig: URL, store: ProfileStore) {
        self.repoConfig = repoConfig
        self.globalConfig = globalConfig
        self.store = store
    }

    /// The `.bouncer` file one scope uses.
    ///
    /// - Parameter scope: The scope.
    /// - Returns: The repo's `.bouncer` or `~/.bouncer`.
    func config(_ scope: SetupScope) -> URL {
        scope == .repo ? repoConfig : globalConfig
    }
}

/// One file the wizard will write: the keys to merge into it.
struct SetupWrite {
    let path: URL
    let payload: [String: Any]
}

/// The config a wizard run starts from: built-in defaults, or a named profile.
struct SetupStart {
    let profileName: String?
    let config: BouncerConfig
}

/// An interactive walkthrough that builds a `.bouncer` file or named profile from a starting point.
///
/// It asks for a starting point, the common settings (each defaulting to the starting point's value), and a
/// save target, then shows exactly which keys it will merge into which files and asks before writing. Only
/// settings that differ from the starting point are written to a `.bouncer` file, alongside a `"profile"` key
/// when starting from one; a profile file instead gets the full starting point plus changes, since profiles
/// can't select other profiles. Existing keys in the target files are kept unless an answer replaces them.
public struct SetupWizard {
    /// The option naming the repo's `.bouncer` file.
    private static let repoConfigOption = "repo .bouncer"
    /// The option naming `~/.bouncer`.
    private static let globalConfigOption = "global ~/.bouncer"

    private let prompt: Prompt
    private let paths: SetupPaths

    /// Creates a setup wizard.
    ///
    /// - Parameters:
    ///   - prompt: The question-asking I/O.
    ///   - paths: The files to read starting points from and write answers to.
    public init(prompt: Prompt, paths: SetupPaths) {
        self.prompt = prompt
        self.paths = paths
    }

    /// Runs the whole walkthrough.
    ///
    /// - Parameters:
    ///   - target: A fixed save target, skipping that question, such as for `bouncer profile create`.
    ///   - preferredScope: The scope the save-target question defaults to.
    /// - Returns: The files written, empty if the user declined or nothing changed.
    /// - Throws: `PromptError.endOfInput` if input ends early, a `ProfileError`, or a file error.
    public func run(target: SetupTarget? = nil, preferredScope: SetupScope = .repo) throws -> [URL] {
        let start = try chooseStart()
        let changes = try SetupQuestions(prompt: prompt, base: start.config).ask()
        let chosen = try target ?? chooseTarget(preferredScope: preferredScope)
        let writes = try plan(start: start, changes: changes, target: chosen)
        return try confirmAndWrite(writes)
    }

    /// Asks which config to start from, defaulting to the profile currently in effect.
    ///
    /// - Returns: The chosen starting point.
    /// - Throws: `PromptError.endOfInput`, or an error loading the chosen profile.
    func chooseStart() throws -> SetupStart {
        let listings = uniqueListings()
        let labels = ["built-in defaults"] + listings.map { "\($0.name) (\($0.source.rawValue) profile)" }
        let current = try currentProfileName()
        let defaultLabel = listings.firstIndex { $0.name == current }.map { labels[$0 + 1] } ?? labels[0]
        let answer = try prompt.choice("Start from?", options: labels, default: defaultLabel)
        let index = labels.firstIndex(of: answer) ?? 0
        return try start(named: index > 0 ? listings[index - 1].name : nil)
    }

    /// Loads a starting point.
    ///
    /// - Parameter name: The profile to start from, or `nil` for built-in defaults.
    /// - Returns: The starting point.
    /// - Throws: An error loading the profile.
    private func start(named name: String?) throws -> SetupStart {
        SetupStart(profileName: name, config: try name.map(paths.store.config(named:)) ?? .empty)
    }

    /// Asks where to save, and for a profile, its name.
    ///
    /// - Parameter preferredScope: The scope the question defaults to.
    /// - Returns: The chosen target.
    /// - Throws: `PromptError.endOfInput` if input ends first.
    func chooseTarget(preferredScope: SetupScope) throws -> SetupTarget {
        let options = [
            Self.repoConfigOption, Self.globalConfigOption,
            "repo profile (.bouncer-profiles/)", "global profile (~/.bouncer-profiles/)"
        ]
        let answer = try prompt.choice("Save to?", options: options, default: options[preferredScope == .repo ? 0 : 1])
        let index = options.firstIndex(of: answer) ?? 0
        let scope: SetupScope = index % 2 == 0 ? .repo : .global
        return index < 2 ? .config(scope) : .profile(name: try askProfileName(), scope: scope)
    }

    /// Asks for a profile name until it's a valid one.
    ///
    /// - Returns: The validated name.
    /// - Throws: `PromptError.endOfInput` if input ends first.
    private func askProfileName() throws -> String {
        while true {
            let name = try prompt.text("Profile name", default: nil)
            do { try ProfileStore.validate(name); return name } catch { prompt.say("  \(error)") }
        }
    }

    /// Builds the writes a target needs: the settings, plus a default-profile pointer if asked for.
    ///
    /// - Parameters:
    ///   - start: The starting point.
    ///   - changes: The answers that differ from it.
    ///   - target: Where to save.
    /// - Returns: The files to write and what to merge into each.
    /// - Throws: `PromptError.endOfInput`, an invalid profile name, or an encoding error.
    func plan(start: SetupStart, changes: BouncerConfig, target: SetupTarget) throws -> [SetupWrite] {
        switch target {
        case .config(let scope):
            var payload = try ConfigFileJSON.object(from: changes)
            if let name = start.profileName { payload["profile"] = name }
            return payload.isEmpty ? [] : [SetupWrite(path: paths.config(scope), payload: payload)]
        case .profile(let name, let scope):
            return try profileWrites(name: name, scope: scope, config: start.config.merging(changes))
        }
    }

    /// Builds a profile file's write, and optionally a `.bouncer` write selecting it as the default.
    ///
    /// - Parameters:
    ///   - name: The profile's name.
    ///   - scope: Whether it's a repo or global profile.
    ///   - config: The profile's full contents.
    /// - Returns: The profile write, followed by the default-pointer write if requested.
    /// - Throws: `PromptError.endOfInput`, an invalid name, or an encoding error.
    private func profileWrites(name: String, scope: SetupScope, config: BouncerConfig) throws -> [SetupWrite] {
        guard let path = try paths.store.fileURL(for: name, in: scope.profileSource) else {
            throw ProfileError.notFound(name: name, searched: [scope.rawValue])
        }
        var profile = config
        (profile.profile, profile.hooks) = (nil, nil)
        let write = SetupWrite(path: path, payload: try ConfigFileJSON.object(from: profile))
        let defaultScope = try askDefaultScope(name: name, scope: scope)
        return [write] + (defaultScope.map { [SetupWrite(path: paths.config($0), payload: ["profile": name])] } ?? [])
    }

    /// Asks whether to make a new profile the default, and where.
    ///
    /// A repo profile can only be a repo default, since other repos can't see it.
    ///
    /// - Parameters:
    ///   - name: The profile's name.
    ///   - scope: Whether it's a repo or global profile.
    /// - Returns: Which `.bouncer` to point at it, or `nil` for neither.
    /// - Throws: `PromptError.endOfInput` if input ends first.
    private func askDefaultScope(name: String, scope: SetupScope) throws -> SetupScope? {
        let repoOptions = ["no", Self.repoConfigOption]
        let options = scope == .repo ? repoOptions : repoOptions + [Self.globalConfigOption]
        let answer = try prompt.choice("Make \"\(name)\" the default profile?", options: options, default: "no")
        switch options.firstIndex(of: answer) {
        case 1: return .repo
        case 2: return .global
        default: return nil
        }
    }

    /// Shows what will be written, asks to confirm, and merges each payload into its file.
    ///
    /// - Parameter writes: The planned writes.
    /// - Returns: The files written, empty if there was nothing to write or the user declined.
    /// - Throws: `PromptError.endOfInput`, or a file read/write error.
    func confirmAndWrite(_ writes: [SetupWrite]) throws -> [URL] {
        guard try confirm(writes) else { return [] }
        for write in writes {
            let merged = ConfigFileJSON.deepMerged(try ConfigFileJSON.readObject(at: write.path), with: write.payload)
            try ConfigFileJSON.write(merged, to: write.path)
            prompt.say("Wrote \(write.path.path).")
        }
        return writes.map(\.path)
    }

    /// Summarizes the planned writes and asks whether to go ahead.
    ///
    /// - Parameter writes: The planned writes.
    /// - Returns: `false` if there's nothing to write or the user declined, with a note saying so.
    /// - Throws: `PromptError.endOfInput`, or an error reading an existing target file.
    private func confirm(_ writes: [SetupWrite]) throws -> Bool {
        guard !writes.isEmpty else {
            prompt.say("Nothing differs from the starting point; nothing written.")
            return false
        }
        try writes.forEach(summarize)
        let approved = try prompt.yesNo("Write these settings?", default: true)
        if !approved { prompt.say("Nothing written.") }
        return approved
    }

    /// Prints one planned write's keys, noting a profile its file already selects.
    ///
    /// - Parameter write: The planned write.
    /// - Throws: If the existing file can't be parsed.
    private func summarize(_ write: SetupWrite) throws {
        prompt.say("Will merge into \(write.path.path):")
        let lines = write.payload.isEmpty ? ["(an empty profile)"] : ConfigFileJSON.dottedLines(write.payload)
        lines.forEach { prompt.say("  \($0)") }
        let existing = try ConfigFileJSON.readObject(at: write.path)["profile"] as? String
        if let existing, write.payload["profile"] == nil {
            prompt.say("  (this file already selects profile \"\(existing)\", which still applies beneath it)")
        }
    }

    /// The profile the repo and global `.bouncer` files currently select, if any.
    ///
    /// - Returns: The repo's `"profile"`, else the global one's, else `nil`.
    /// - Throws: If either file exists but isn't valid JSON.
    private func currentProfileName() throws -> String? {
        let loader = ConfigLoader()
        let files = [try loader.read(paths.repoConfig), try loader.read(paths.globalConfig)]
        return ConfigLoader.effectiveProfileName(cli: nil, files: files)
    }

    /// Every profile name the store can see, keeping only the copy that name resolves to.
    ///
    /// - Returns: The first listing for each name, in store order.
    private func uniqueListings() -> [ProfileListing] {
        var seen = Set<String>()
        return paths.store.list().filter { seen.insert($0.name).inserted }
    }
}
