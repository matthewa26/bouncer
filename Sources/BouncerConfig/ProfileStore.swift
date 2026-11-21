import Foundation

/// Where a named profile lives, in lookup-precedence order.
public enum ProfileSource: String, Sendable, Equatable, CaseIterable {
    /// `<repoRoot>/.bouncer-profiles/<name>.json`.
    case repo
    /// `~/.bouncer-profiles/<name>.json`.
    case global
    /// A preset compiled into Bouncer, such as `kirby`.
    case bundled
}

/// One profile a `ProfileStore` found.
public struct ProfileListing: Sendable, Equatable {
    /// The profile's name, its file name without `.json`.
    public let name: String
    /// Where the profile was found.
    public let source: ProfileSource
    /// The profile file, or `nil` for a bundled preset.
    public let path: URL?
}

/// Finds, validates, and loads named profiles: repo files, then global files, then bundled presets.
///
/// A profile file uses the `.bouncer` schema, but may not declare `hooks` (only a `.bouncer` file
/// passes through the hooks trust gate) or `profile` (profiles don't chain).
public struct ProfileStore {
    /// The directory name profile files live in, under a repo root or the home directory.
    public static let directoryName = ".bouncer-profiles"

    /// `<repoRoot>/.bouncer-profiles`, or `nil` outside a repo.
    public let repoDirectory: URL?
    /// `~/.bouncer-profiles`.
    public let globalDirectory: URL
    private let fileManager: FileManager

    /// Creates a profile store rooted at a repo and a home directory.
    ///
    /// - Parameters:
    ///   - repoRoot: The repository root, if any, whose `.bouncer-profiles` is searched first.
    ///   - homeDirectory: The directory holding `~/.bouncer-profiles`, injectable for tests.
    ///   - fileManager: The file manager to read profile files with.
    public init(repoRoot: URL?, homeDirectory: URL, fileManager: FileManager = .default) {
        repoDirectory = repoRoot?.appendingPathComponent(Self.directoryName)
        globalDirectory = homeDirectory.appendingPathComponent(Self.directoryName)
        self.fileManager = fileManager
    }

    /// Rejects a name that could escape the profiles directory or isn't a plain file name.
    ///
    /// - Parameter name: The candidate profile name.
    /// - Throws: `ProfileError.invalidName` unless it's non-empty `[A-Za-z0-9._-]`, and not `.` or `..`.
    public static func validate(_ name: String) throws {
        let isAllowed: (Character) -> Bool = { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
        guard !name.isEmpty, name != ".", name != "..", name.allSatisfy(isAllowed) else {
            throw ProfileError.invalidName(name)
        }
    }

    /// The directory one source's profile files live in.
    ///
    /// - Parameter source: The source to look up.
    /// - Returns: The directory, or `nil` for bundled presets and for `.repo` outside a repo.
    public func directory(for source: ProfileSource) -> URL? {
        switch source {
        case .repo: return repoDirectory
        case .global: return globalDirectory
        case .bundled: return nil
        }
    }

    /// The file a named profile would live at in one source, whether or not it exists.
    ///
    /// - Parameters:
    ///   - name: The profile's name.
    ///   - source: The source whose directory to use.
    /// - Returns: `<directory>/<name>.json`, or `nil` when the source has no directory.
    /// - Throws: `ProfileError.invalidName` for an unsafe name.
    public func fileURL(for name: String, in source: ProfileSource) throws -> URL? {
        try Self.validate(name)
        return directory(for: source)?.appendingPathComponent("\(name).json")
    }

    /// Finds the highest-precedence profile with this name.
    ///
    /// - Parameters:
    ///   - name: The profile's name.
    ///   - sources: The sources to search, in precedence order.
    /// - Returns: The first match.
    /// - Throws: `ProfileError.invalidName` for an unsafe name, or `.notFound` when nothing matches.
    public func locate(_ name: String, in sources: [ProfileSource] = ProfileSource.allCases) throws -> ProfileListing {
        try Self.validate(name)
        if let found = sources.lazy.compactMap({ find(name, in: $0) }).first { return found }
        throw ProfileError.notFound(name: name, searched: sources.compactMap { searchedLocation(of: name, in: $0) })
    }

    /// Loads a named profile's config from wherever it resolves.
    ///
    /// - Parameter name: The profile's name.
    /// - Returns: The profile's config.
    /// - Throws: A `ProfileError` if it's missing, unsafe, or declares hooks or a profile, or a decoding error.
    public func config(named name: String) throws -> BouncerConfig {
        let listing = try locate(name)
        guard let path = listing.path else { return BundledProfiles.config(named: name) ?? .empty }
        return try Self.read(path)
    }

    /// Reads and validates one profile file.
    ///
    /// - Parameter path: The profile file.
    /// - Returns: The decoded config.
    /// - Throws: `ProfileError.containsProfileKey`/`.containsHooks`, or a read/decoding error.
    public static func read(_ path: URL) throws -> BouncerConfig {
        let config = try JSONDecoder().decode(BouncerConfig.self, from: Data(contentsOf: path))
        if config.profile != nil { throw ProfileError.containsProfileKey(path: path.path) }
        let hookCount = (config.hooks?.preCheck ?? []).count + (config.hooks?.postCheck ?? []).count
        if hookCount > 0 { throw ProfileError.containsHooks(path: path.path) }
        return config
    }

    /// Every profile this store can see: repo files, global files, then bundled presets.
    ///
    /// A name can appear more than once; the first occurrence is the one `locate(_:)` resolves.
    ///
    /// - Returns: The listings, sorted by name within each source.
    public func list() -> [ProfileListing] {
        let files = [ProfileSource.repo, .global].flatMap(listFiles(in:))
        return files + BundledProfiles.names.map { ProfileListing(name: $0, source: .bundled, path: nil) }
    }

    /// Finds one named profile in one source.
    ///
    /// - Parameters:
    ///   - name: The already-validated profile name.
    ///   - source: The source to check.
    /// - Returns: The listing, or `nil` if that source has no such profile.
    private func find(_ name: String, in source: ProfileSource) -> ProfileListing? {
        if source == .bundled {
            let isBundled = BundledProfiles.config(named: name) != nil
            return isBundled ? ProfileListing(name: name, source: .bundled, path: nil) : nil
        }
        guard let url = directory(for: source)?.appendingPathComponent("\(name).json"),
              fileManager.fileExists(atPath: url.path) else { return nil }
        return ProfileListing(name: name, source: source, path: url)
    }

    /// Describes where one source was searched, for a not-found error.
    ///
    /// - Parameters:
    ///   - name: The profile name searched for.
    ///   - source: The source searched.
    /// - Returns: The file path checked, "bundled profiles", or `nil` for a source with no directory.
    private func searchedLocation(of name: String, in source: ProfileSource) -> String? {
        source == .bundled ? "bundled profiles" : directory(for: source)?.appendingPathComponent("\(name).json").path
    }

    /// Lists the validly named `.json` files in one source's directory.
    ///
    /// - Parameter source: `.repo` or `.global`.
    /// - Returns: One listing per profile file, sorted by name.
    private func listFiles(in source: ProfileSource) -> [ProfileListing] {
        guard let directory = directory(for: source),
              let entries = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return [] }
        let names = entries.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(".json".count)) }
        return names.filter { (try? Self.validate($0)) != nil }.sorted().map {
            ProfileListing(name: $0, source: source, path: directory.appendingPathComponent("\($0).json"))
        }
    }
}
