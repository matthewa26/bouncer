import Foundation

/// PHP: each file is a node; a `use` resolves through the repository-root `composer.json`'s PSR-4 rules, and a
/// literal `require` or `include` resolves to the file it names.
///
/// A class, interface, trait, or enum name resolves under the longest PSR-4 prefix it starts with
/// (`App\Foo\Bar` with `"App\\": "src/"` is `src/Foo/Bar.php`), trying shorter prefixes and each listed folder
/// in turn, as Composer does, and counts only when that file is indexed. A `use function` or `use const`
/// resolves to its namespace's file (`function App\Support\helper` to `src/Support.php`) only when that file
/// exists; functions usually live in `autoload.files` entries that no name maps to, so most add no edge.
/// `require __DIR__ . '/x.php'` is relative to the requiring file's folder; a plain literal path is tried there
/// and then at the repository root. Without a readable `composer.json`, `use` adds no edges.
struct PHPImportResolver: ImportResolver {
    /// The extensions this resolver handles.
    static let extensions = ["php", "phtml"]
    /// The prefix `PHPModuleFacts` gives literal inclusions.
    private static let requirePrefix = "require "
    /// The marker for a path relative to the including file's folder.
    private static let directoryMarker = "__DIR__"
    /// The keywords a function or constant `use` keeps.
    private static let memberKinds = ["function ", "const "]

    private let paths: Set<String>
    private let prefixes: [ComposerManifest.Prefix]

    /// Creates the resolver over the project's files and the root `composer.json`.
    ///
    /// - Parameters:
    ///   - paths: Every indexed file's repo-relative path.
    ///   - repoRoot: The repository root, for `composer.json`.
    init(paths: Set<String>, repoRoot: URL) {
        self.paths = paths
        prefixes = ComposerManifest.read("composer.json", repoRoot: repoRoot)?.prefixes ?? []
    }

    /// The node for a PHP file: the file itself.
    ///
    /// - Parameter path: The file's repo-relative path.
    /// - Returns: The path.
    func node(of path: String) -> String { path }

    /// Resolves a `use` name or a literal inclusion, as `PHPModuleFacts` records them.
    ///
    /// - Parameters:
    ///   - specifier: `App\Foo`, `function App\f`, `const App\C`, `require x.php`, or `require __DIR__/x.php`.
    ///   - path: The importing file.
    /// - Returns: The file, or `nil` for a vendor class, a computed or missing path, or no PSR-4 match.
    func resolve(_ specifier: String, from path: String) -> String? {
        if specifier.hasPrefix(Self.requirePrefix) {
            return includedFile(String(specifier.dropFirst(Self.requirePrefix.count)), from: path)
        }
        guard let kind = Self.memberKinds.first(where: specifier.hasPrefix) else { return classFile(specifier) }
        let member = specifier.dropFirst(kind.count)
        return member.lastIndex(of: "\\").flatMap { classFile(String(member[..<$0])) }
    }

    /// Finds a class's file under the PSR-4 rules.
    ///
    /// - Parameter name: A fully qualified name, such as `App\Foo\Bar`.
    /// - Returns: The first indexed file a matching prefix maps it to.
    func classFile(_ name: String) -> String? {
        let matching = prefixes.filter { name.hasPrefix($0.namespace) }
        return matching.lazy.compactMap { prefix in
            let relative = name.dropFirst(prefix.namespace.count).replacingOccurrences(of: "\\", with: "/") + ".php"
            return prefix.directories.lazy.compactMap { self.indexed(ProjectPath.join($0, relative)) }.first
        }.first
    }

    /// Finds an included file.
    ///
    /// - Parameters:
    ///   - written: The path, `__DIR__`-prefixed when it's relative to the including file's folder.
    ///   - path: The including file.
    /// - Returns: The indexed file, or `nil`.
    private func includedFile(_ written: String, from path: String) -> String? {
        let folder = ProjectPath.directory(of: path)
        if written.hasPrefix(Self.directoryMarker) {
            return indexed(ProjectPath.join(folder, String(written.dropFirst(Self.directoryMarker.count))))
        }
        guard !written.hasPrefix("/") else { return nil }
        return indexed(ProjectPath.join(folder, written)) ?? indexed(ProjectPath.join("", written))
    }

    /// Keeps a path only if it's indexed.
    ///
    /// - Parameter path: A repo-relative path, or `nil`.
    /// - Returns: The path, if indexed.
    private func indexed(_ path: String?) -> String? {
        path.flatMap { paths.contains($0) ? $0 : nil }
    }
}
