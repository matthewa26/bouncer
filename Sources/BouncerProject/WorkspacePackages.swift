import Foundation

/// The repo's own JavaScript packages, from every `package.json` above a source file, so an import of a
/// sibling workspace package (`@acme/ui`, `@acme/ui/button`) resolves to its source instead of being external.
struct WorkspacePackages: Sendable {
    /// One package: its name, folder, and the entry and subpath fields from its `package.json`.
    private struct Package: Sendable {
        let name: String
        let directory: String
        let entries: [String]
        let subpaths: [String: String]
    }

    private static let buildFolders = ["dist/", "build/", "lib/", "out/"]
    private let packages: [Package]

    /// Reads every `package.json` at or above the given folders.
    ///
    /// - Parameters:
    ///   - directories: The repo-relative folders holding source files.
    ///   - repoRoot: The repository root.
    init(directories: Set<String>, repoRoot: URL) {
        let manifests = NearestFiles.all(named: "package.json", above: directories, repoRoot: repoRoot)
        packages = manifests.compactMap { Self.package(at: $0, repoRoot: repoRoot) }
            .sorted { $0.name.count > $1.name.count }
    }

    /// Lists the base paths an import of a workspace package could mean, most specific first.
    ///
    /// - Parameter specifier: The import as written.
    /// - Returns: Repo-relative candidates without extensions, or none if no workspace package matches.
    func candidates(for specifier: String) -> [String] {
        guard let package = packages.first(where: { specifier == $0.name || specifier.hasPrefix($0.name + "/") }) else {
            return []
        }
        let subpath = String(specifier.dropFirst(package.name.count).drop { $0 == "/" })
        let relative = subpath.isEmpty
            ? package.entries + ["src/index", "index"]
            : [package.subpaths["./" + subpath]].compactMap { $0 } + [subpath, "src/" + subpath]
        return relative.flatMap(Self.sourceVariants).compactMap { ProjectPath.join(package.directory, $0) }
    }

    /// Lists a path and, for build output such as `dist/index.js`, the matching `src/` path.
    ///
    /// - Parameter path: A package-relative path.
    /// - Returns: The path, then its source equivalent if it's under a build folder.
    private static func sourceVariants(_ path: String) -> [String] {
        let trimmed = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
        let build = buildFolders.first { trimmed.hasPrefix($0) }
        return [trimmed] + (build.map { ["src/" + trimmed.dropFirst($0.count)] } ?? [])
    }

    /// Reads one `package.json`.
    ///
    /// - Parameters:
    ///   - path: The manifest's repo-relative path.
    ///   - repoRoot: The repository root.
    /// - Returns: The package, or `nil` without a `name`.
    private static func package(at path: String, repoRoot: URL) -> Package? {
        guard let manifest = TSConfig.readJSONC(path, repoRoot: repoRoot),
              let name = manifest["name"] as? String else { return nil }
        let exports = manifest["exports"]
        let fields = ["source", "module", "main", "types"].compactMap { manifest[$0] as? String }
        let entries = [entry(exports)].compactMap { $0 } + fields
        return Package(name: name, directory: ProjectPath.directory(of: path),
                       entries: entries, subpaths: subpaths(exports))
    }

    /// Reads the main entry from an `exports` field: a string, or the `.` key's string or conditions.
    ///
    /// - Parameter exports: The `exports` value.
    /// - Returns: The entry path, if any.
    private static func entry(_ exports: Any?) -> String? {
        if let path = exports as? String { return path }
        return condition((exports as? [String: Any])?["."])
    }

    /// Reads each `./subpath` key of an `exports` field.
    ///
    /// - Parameter exports: The `exports` value.
    /// - Returns: Each subpath's target path.
    private static func subpaths(_ exports: Any?) -> [String: String] {
        let keyed = (exports as? [String: Any] ?? [:]).filter { $0.key.hasPrefix("./") && $0.key != "./" }
        return keyed.compactMapValues(condition)
    }

    /// Picks a path from an export target: a string, or the first of `source`, `import`, `default`,
    /// `require`, and `types` in a conditions object.
    ///
    /// - Parameter target: The export target.
    /// - Returns: The path, if any.
    private static func condition(_ target: Any?) -> String? {
        if let path = target as? String { return path }
        let conditions = target as? [String: Any] ?? [:]
        return ["source", "import", "default", "require", "types"].lazy.compactMap { conditions[$0] as? String }.first
    }
}
