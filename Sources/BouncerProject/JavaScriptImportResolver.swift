import Foundation
import BouncerCore

/// TypeScript/JavaScript: each file is a node. Relative specifiers, path aliases from the nearest
/// `tsconfig.json`, and imports of the repo's own workspace packages resolve to files, trying TypeScript and
/// JavaScript extensions and `index` files; third-party packages are external.
struct JavaScriptImportResolver: ImportResolver {
    static let extensions = ["ts", "tsx", "mts", "cts", "js", "jsx", "mjs", "cjs"]
    private let paths: Set<String>
    private let configByDirectory: [String: TSConfig]
    private let workspace: WorkspacePackages

    /// Creates the resolver over the project's files, reading each folder's nearest `tsconfig.json` and every
    /// `package.json` above a source file.
    ///
    /// - Parameters:
    ///   - paths: Every indexed file's repo-relative path.
    ///   - repoRoot: The repository root.
    init(paths: Set<String>, repoRoot: URL) {
        self.paths = paths
        let sources = paths.filter { Self.extensions.contains(($0 as NSString).pathExtension.lowercased()) }
        let directories = Set(sources.map(ProjectPath.directory))
        let nearest = NearestFiles(named: "tsconfig.json", from: directories, repoRoot: repoRoot).byDirectory
        let configs = Dictionary(
            uniqueKeysWithValues: Set(nearest.values).map { ($0, TSConfig.load($0, repoRoot: repoRoot)) }
        )
        configByDirectory = nearest.compactMapValues { configs[$0] }
        workspace = WorkspacePackages(directories: directories, repoRoot: repoRoot)
    }

    /// The node for a TS/JS file: the file itself.
    ///
    /// - Parameter path: The file's repo-relative path.
    /// - Returns: The path.
    func node(of path: String) -> String { path }

    /// Resolves a relative or aliased specifier to a project file.
    ///
    /// - Parameters:
    ///   - specifier: The import as written.
    ///   - path: The importing file.
    /// - Returns: The imported file, or `nil` for a package or unresolvable import.
    func resolve(_ specifier: String, from path: String) -> String? {
        let directory = ProjectPath.directory(of: path)
        let bases = specifier.hasPrefix(".")
            ? [ProjectPath.join(directory, specifier)].compactMap { $0 }
            : (configByDirectory[directory] ?? .none).candidates(for: specifier) + workspace.candidates(for: specifier)
        return bases.lazy.compactMap(file(for:)).first
    }

    /// Finds the file a resolved base path refers to.
    ///
    /// - Parameter base: A path that may lack its extension, name a directory, or use `.js` for a `.ts` file.
    /// - Returns: The first existing candidate file.
    private func file(for base: String) -> String? {
        let path = base as NSString
        let stem = Self.extensions.contains(path.pathExtension) ? path.deletingPathExtension : base
        let candidates = [base] + Self.extensions.map { stem + "." + $0 }
            + Self.extensions.map { base + "/index." + $0 }
        return candidates.first(where: paths.contains)
    }
}
