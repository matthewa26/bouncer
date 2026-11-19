import Foundation

/// Module resolution settings from one `tsconfig.json`, after following its relative `extends` chain.
///
/// `baseUrl` is resolved against the config that sets it. `paths` are resolved against `baseUrl` when one
/// is in effect, otherwise against the folder of the config that declares them, as TypeScript does.
struct TSConfig: Sendable {
    private(set) var baseUrl: String?
    private(set) var paths: [String: [String]] = [:]
    private(set) var pathsBase = ""

    /// A config with no settings, for files no `tsconfig.json` covers.
    static let none = TSConfig()

    /// Lists the base paths a non-relative specifier could mean: each matching `paths` alias, then `baseUrl`.
    ///
    /// - Parameter specifier: The import as written.
    /// - Returns: Repo-relative candidates, without extensions.
    func candidates(for specifier: String) -> [String] {
        let aliased = paths.flatMap { pattern, targets in
            Self.match(specifier, pattern).map { rest in
                targets.map { $0.replacingOccurrences(of: "*", with: rest) }
            } ?? []
        }.compactMap { ProjectPath.join(pathsBase, $0) }
        let fromBase = baseUrl.flatMap { ProjectPath.join($0, specifier) }
        return aliased + (fromBase.map { [$0] } ?? [])
    }

    /// Loads a config and the configs it extends.
    ///
    /// - Parameters:
    ///   - path: The config's repo-relative path.
    ///   - repoRoot: The repository root.
    ///   - depth: How many `extends` hops deep this is, to stop cycles.
    /// - Returns: The merged settings.
    static func load(_ path: String, repoRoot: URL, depth: Int = 0) -> TSConfig {
        let object = readJSONC(path, repoRoot: repoRoot)
        let parent = (object?["extends"] as? String).flatMap { extended in
            depth < 8 ? extendedPath(extended, from: path).map { load($0, repoRoot: repoRoot, depth: depth + 1) } : nil
        } ?? .none
        let options = object?["compilerOptions"] as? [String: Any] ?? [:]
        return parent.applying(options, declaredIn: ProjectPath.directory(of: path))
    }

    /// Overlays one config's `compilerOptions` on the settings it extends.
    ///
    /// - Parameters:
    ///   - options: The config's `compilerOptions`.
    ///   - directory: The config's repo-relative folder.
    /// - Returns: The merged settings.
    private func applying(_ options: [String: Any], declaredIn directory: String) -> TSConfig {
        var merged = self
        if let base = options["baseUrl"] as? String { merged.baseUrl = ProjectPath.join(directory, base) }
        if let paths = options["paths"] as? [String: [String]] {
            merged.paths = paths
            merged.pathsBase = directory
        }
        if let baseUrl = merged.baseUrl { merged.pathsBase = baseUrl }
        return merged
    }

    /// Resolves an `extends` value that's a relative path; package configs such as `@tsconfig/node18` are skipped.
    ///
    /// - Parameters:
    ///   - extended: The `extends` value.
    ///   - path: The extending config's repo-relative path.
    /// - Returns: The extended config's repo-relative path, or `nil` for a package config.
    private static func extendedPath(_ extended: String, from path: String) -> String? {
        guard extended.hasPrefix(".") else { return nil }
        let file = extended.hasSuffix(".json") ? extended : extended + ".json"
        return ProjectPath.join(ProjectPath.directory(of: path), file)
    }

    /// Reads a JSON-with-comments file as a dictionary.
    ///
    /// - Parameters:
    ///   - path: The file's repo-relative path.
    ///   - repoRoot: The repository root.
    /// - Returns: The parsed object, or `nil` if it's missing or malformed.
    static func readJSONC(_ path: String, repoRoot: URL) -> [String: Any]? {
        let url = path.split(separator: "/").reduce(repoRoot) { $0.appendingPathComponent(String($1)) }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(stripJSONC(text).utf8))) as? [String: Any]
    }

    /// Matches a specifier against a `paths` pattern with at most one `*`.
    ///
    /// - Parameters:
    ///   - specifier: The import as written.
    ///   - pattern: The alias pattern, such as `@app/*`.
    /// - Returns: The text the `*` matched (empty for an exact match), or `nil` if it doesn't match.
    private static func match(_ specifier: String, _ pattern: String) -> String? {
        guard let star = pattern.firstIndex(of: "*") else { return specifier == pattern ? "" : nil }
        let prefix = pattern[..<star], suffix = pattern[pattern.index(after: star)...]
        let fits = specifier.hasPrefix(prefix) && specifier.hasSuffix(suffix)
        guard fits, specifier.count >= prefix.count + suffix.count else { return nil }
        return String(specifier.dropFirst(prefix.count).dropLast(suffix.count))
    }

    /// Removes `//` and `/* */` comments and trailing commas, which `tsconfig.json` allows and JSON doesn't.
    ///
    /// - Parameter text: The file's text.
    /// - Returns: Plain JSON.
    static func stripJSONC(_ text: String) -> String {
        let withoutComments = text.replacingOccurrences(
            of: #"("(?:\\.|[^"\\])*")|//[^\n]*|/\*[\s\S]*?\*/"#, with: "$1", options: .regularExpression
        )
        return withoutComments.replacingOccurrences(of: #",(\s*[}\]])"#, with: "$1", options: .regularExpression)
    }
}

/// Finds the nearest file with a given name above each folder, reading the disk once per folder.
struct NearestFiles: Sendable {
    /// Each folder's nearest matching file, as a repo-relative path.
    let byDirectory: [String: String]

    /// Searches upward from each folder to the repo root.
    ///
    /// - Parameters:
    ///   - name: The file name, such as `tsconfig.json`.
    ///   - directories: The repo-relative folders to search from.
    ///   - repoRoot: The repository root.
    init(named name: String, from directories: Set<String>, repoRoot: URL) {
        var memo: [String: String?] = [:]
        for directory in directories { _ = Self.nearest(name, from: directory, repoRoot: repoRoot, memo: &memo) }
        byDirectory = memo.compactMapValues { $0 }
    }

    /// Every folder on the way from each search start up to the root that holds a matching file.
    ///
    /// - Parameters:
    ///   - name: The file name.
    ///   - directories: The folders to search from.
    ///   - repoRoot: The repository root.
    /// - Returns: Every matching file's repo-relative path.
    static func all(named name: String, above directories: Set<String>, repoRoot: URL) -> Set<String> {
        let ancestors = directories.flatMap { directory in
            let parts = directory.split(separator: "/")
            return (0...parts.count).map { parts.prefix($0).joined(separator: "/") }
        }
        return Set(Set(ancestors).compactMap { exists(name, in: $0, repoRoot: repoRoot) })
    }

    /// Finds the nearest file at or above one folder, memoizing every folder visited.
    ///
    /// - Parameters:
    ///   - name: The file name.
    ///   - directory: The folder to start from.
    ///   - repoRoot: The repository root.
    ///   - memo: Folders already searched.
    /// - Returns: The nearest file's repo-relative path, or `nil` if none exists up to the root.
    private static func nearest(
        _ name: String, from directory: String, repoRoot: URL, memo: inout [String: String?]
    ) -> String? {
        if let known = memo[directory] { return known }
        let here = exists(name, in: directory, repoRoot: repoRoot)
        let found = here ?? (directory.isEmpty
            ? nil
            : nearest(name, from: ProjectPath.directory(of: directory), repoRoot: repoRoot, memo: &memo))
        memo[directory] = .some(found)
        return found
    }

    /// Checks whether a folder holds a file.
    ///
    /// - Parameters:
    ///   - name: The file name.
    ///   - directory: The repo-relative folder.
    ///   - repoRoot: The repository root.
    /// - Returns: The file's repo-relative path if it exists.
    private static func exists(_ name: String, in directory: String, repoRoot: URL) -> String? {
        let path = directory.isEmpty ? name : directory + "/" + name
        let url = path.split(separator: "/").reduce(repoRoot) { $0.appendingPathComponent(String($1)) }
        return FileManager.default.fileExists(atPath: url.path) ? path : nil
    }
}
