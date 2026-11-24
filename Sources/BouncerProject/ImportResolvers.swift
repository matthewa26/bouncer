import Foundation
import BouncerCore

/// Turns one language's import specifiers into project nodes.
public protocol ImportResolver: Sendable { // bouncer:disable-line parallel-inheritance -- one per language, by design
    /// The node a file belongs to: the file itself, or its Swift target or Go package.
    ///
    /// - Parameter path: The repo-relative file path.
    /// - Returns: The node's identifier.
    func node(of path: String) -> String

    /// Resolves an import to the project node it refers to.
    ///
    /// - Parameters:
    ///   - specifier: The import as written.
    ///   - path: The importing file's repo-relative path.
    /// - Returns: The imported node, or `nil` for anything outside the project.
    func resolve(_ specifier: String, from path: String) -> String?
}

/// Picks each file's resolver by its extension.
public struct ImportResolvers: Sendable {
    private let byExtension: [String: ImportResolver]

    /// Builds resolvers for every language present in the project.
    ///
    /// - Parameters:
    ///   - paths: Every indexed file's repo-relative path.
    ///   - repoRoot: The repository root, for `tsconfig.json`, `go.mod`, `Cargo.toml`, and `composer.json`.
    public init(paths: Set<String>, repoRoot: URL) {
        var resolvers = Self.multiExtension(paths: paths, repoRoot: repoRoot)
        resolvers["swift"] = SwiftImportResolver(paths: paths)
        resolvers["py"] = PythonImportResolver(paths: paths)
        resolvers["rs"] = RustImportResolver(paths: paths, repoRoot: repoRoot)
        if let module = GoImportResolver.modulePath(repoRoot: repoRoot) {
            resolvers["go"] = GoImportResolver(module: module)
        }
        byExtension = resolvers
    }

    /// Builds the resolvers that handle several extensions each: TS/JS, Objective-C, and PHP.
    ///
    /// - Parameters:
    ///   - paths: Every indexed file's repo-relative path.
    ///   - repoRoot: The repository root, for `tsconfig.json` and `composer.json`.
    /// - Returns: Each extension's resolver.
    private static func multiExtension(paths: Set<String>, repoRoot: URL) -> [String: ImportResolver] {
        let shared: [([String], ImportResolver)] = [
            (JavaScriptImportResolver.extensions, JavaScriptImportResolver(paths: paths, repoRoot: repoRoot)),
            (ObjCImportResolver.extensions, ObjCImportResolver(paths: paths)),
            (PHPImportResolver.extensions, PHPImportResolver(paths: paths, repoRoot: repoRoot))
        ]
        return Dictionary(shared.flatMap { extensions, resolver in extensions.map { ($0, resolver) } }) { $1 }
    }

    /// Looks up the resolver for a file.
    ///
    /// - Parameter path: The repo-relative file path.
    /// - Returns: Its language's resolver, or `nil` for a language without one.
    func resolver(for path: String) -> ImportResolver? {
        byExtension[(path as NSString).pathExtension.lowercased()]
    }
}

/// Repo-relative path arithmetic with `/` separators.
enum ProjectPath {
    /// The directory part of a path, or `""` for a file at the root.
    ///
    /// - Parameter path: A repo-relative path.
    /// - Returns: Its directory.
    static func directory(of path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }

    /// Joins and normalizes path components, resolving `.` and `..`.
    ///
    /// - Parameters:
    ///   - base: A repo-relative directory.
    ///   - relative: A path relative to it.
    /// - Returns: The normalized repo-relative path, or `nil` if it climbs above the root.
    static func join(_ base: String, _ relative: String) -> String? {
        var parts: [Substring] = base.split(separator: "/")
        for part in relative.split(separator: "/") where part != "." {
            guard apply(part, to: &parts) else { return nil }
        }
        return parts.joined(separator: "/")
    }

    /// Applies one path component: `..` pops the last part, anything else is appended.
    ///
    /// - Parameters:
    ///   - part: A path component other than `.`.
    ///   - parts: The components joined so far.
    /// - Returns: `false` if `..` climbs above the root, otherwise `true`.
    private static func apply(_ part: Substring, to parts: inout [Substring]) -> Bool {
        if part == ".." { return parts.popLast() != nil }
        parts.append(part)
        return true
    }
}

/// Swift: a file's node is its SwiftPM target (`Sources/<Target>/…`), and `import X` resolves to target `X`.
struct SwiftImportResolver: ImportResolver {
    private let targets: Set<String>

    /// Creates the resolver, noting which targets exist.
    ///
    /// - Parameter paths: Every indexed file's repo-relative path.
    init(paths: Set<String>) {
        targets = Set(paths.filter { $0.hasSuffix(".swift") }.map { Self.target(of: $0) })
    }

    /// The node for a Swift file's target.
    ///
    /// - Parameter path: The file's repo-relative path.
    /// - Returns: `swift:<Target>`.
    func node(of path: String) -> String { "swift:" + Self.target(of: path) }

    /// Resolves `import X` to target `X` when the project defines it.
    ///
    /// - Parameters:
    ///   - specifier: The imported module.
    ///   - path: The importing file.
    /// - Returns: The target's node, or `nil` for a system or package module.
    func resolve(_ specifier: String, from path: String) -> String? {
        targets.contains(specifier) ? "swift:" + specifier : nil
    }

    /// Finds the target a file belongs to: the folder under `Sources/` or `Tests/`, else its top folder.
    ///
    /// - Parameter path: The file's repo-relative path.
    /// - Returns: The target name.
    static func target(of path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        if let index = parts.firstIndex(where: { $0 == "Sources" || $0 == "Tests" }), index + 1 < parts.count - 1 {
            return parts[index + 1]
        }
        return parts.count > 1 ? parts[0] : ""
    }
}

/// Python: each file is a node; `a.b` resolves to `a/b.py` or `a/b/__init__.py` at the root or under
/// `src/`, and relative imports (`.x`, `..x`) resolve from the importing file's package.
struct PythonImportResolver: ImportResolver {
    private let paths: Set<String>

    /// Creates the resolver over the project's files.
    ///
    /// - Parameter paths: Every indexed file's repo-relative path.
    init(paths: Set<String>) { self.paths = paths }

    /// The node for a Python file: the file itself.
    ///
    /// - Parameter path: The file's repo-relative path.
    /// - Returns: The path.
    func node(of path: String) -> String { path }

    /// Resolves a dotted or relative module to a project file.
    ///
    /// - Parameters:
    ///   - specifier: The module, such as `pkg.mod` or `..mod`.
    ///   - path: The importing file.
    /// - Returns: The module's file, or `nil` for anything outside the project.
    func resolve(_ specifier: String, from path: String) -> String? {
        let dots = specifier.prefix { $0 == "." }.count
        let module = specifier.dropFirst(dots).replacingOccurrences(of: ".", with: "/")
        let bases = dots > 0
            ? [ProjectPath.join(ProjectPath.directory(of: path), String(repeating: "../", count: dots - 1))]
                .compactMap { $0 }
            : ["", "src"]
        return bases.lazy.compactMap { base in self.file(for: base.isEmpty ? module : base + "/" + module) }.first
    }

    /// Finds the file for a module path.
    ///
    /// - Parameter base: The module's path without an extension.
    /// - Returns: `base.py` or `base/__init__.py`, whichever exists.
    private func file(for base: String) -> String? {
        [base + ".py", base + "/__init__.py"].first(where: paths.contains)
    }
}

/// Go: each package directory is a node, and imports under the `go.mod` module path resolve to it.
struct GoImportResolver: ImportResolver {
    let module: String

    /// Reads the module path from the repo's `go.mod`.
    ///
    /// - Parameter repoRoot: The repository root.
    /// - Returns: The module path, or `nil` without a `go.mod`.
    static func modulePath(repoRoot: URL) -> String? {
        let url = repoRoot.appendingPathComponent("go.mod")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let line = SourceFile.lines(of: text).first { $0.hasPrefix("module ") }
        return line.map { $0.dropFirst("module ".count).trimmingCharacters(in: .whitespaces) }
    }

    /// The node for a Go file's package directory.
    ///
    /// - Parameter path: The file's repo-relative path.
    /// - Returns: `go:<directory>`.
    func node(of path: String) -> String { "go:" + ProjectPath.directory(of: path) }

    /// Resolves an import under this module to its package directory.
    ///
    /// - Parameters:
    ///   - specifier: The import path.
    ///   - path: The importing file.
    /// - Returns: The package's node, or `nil` for standard-library and third-party packages.
    func resolve(_ specifier: String, from path: String) -> String? {
        guard specifier == module || specifier.hasPrefix(module + "/") else { return nil }
        return "go:" + specifier.dropFirst(module.count).drop { $0 == "/" }
    }
}
