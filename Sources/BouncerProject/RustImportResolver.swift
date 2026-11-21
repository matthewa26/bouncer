import Foundation

/// Rust: each file is a node, and module declarations and `use` paths resolve to the files of the modules they
/// name.
///
/// A crate's modules live under its source folder: the folder of its root file (`src/lib.rs`, `src/main.rs`,
/// `src/bin/tool.rs`, `tests/it.rs`, `build.rs`, …). Module `a::b` is `a/b.rs` or `a/b/mod.rs` there, so `mod b;` in
/// `src/a.rs` is `src/a/b.rs`, and in `src/lib.rs` or `src/a/mod.rs` it's the file beside it. A `use` path starts
/// at the crate root (`crate::`), the current module (`self::`, a child module's name), its parent (`super::`), or
/// another crate (`other_crate::`, which resolves only to a workspace member's library, from `CargoWorkspace`).
/// Each later segment that names a module file goes one module deeper; the first that doesn't is an item in the
/// module reached so far, which is the edge's target.
///
/// Only a crate root's `mod` declarations are edges. A nested module's `mod` declarations only place its children
/// in the tree: a `use` of an item in `a/mod.rs` from elsewhere would otherwise reach every module under `a`, and
/// make a cycle of any path back. What a nested module really depends on shows in its `use` paths (`pub use
/// self::child::Item` included). Likewise, a `use` of an item in the importing file's own ancestor module (`use
/// crate::Error` from a child, `use super::*`) isn't an edge, or every child reaching back up would be a cycle.
/// `#[path = "…"]` attributes, `include!`, and macro-generated modules aren't followed.
struct RustImportResolver: ImportResolver {
    /// The extension this resolver handles.
    static let extensions = ["rs"]
    /// Package folders whose every `.rs` file directly inside is a crate root of its own; `bin` counts only as
    /// `src/bin`, and the others only outside `src`, where a `tests` folder is just a module.
    private static let rootFolders: Set<String> = ["tests", "examples", "benches"]
    private static let rootFileNames: Set<String> = ["lib.rs", "main.rs", "build.rs"]
    /// The path segment naming the parent module.
    private static let superSegment = "super"

    private let paths: Set<String>
    private let workspace: [String: String]

    /// A module: the crate source folder it's under, and its path from the crate root.
    private struct Module: Equatable {
        let base: String
        var path: [String]

        /// Climbs to an ancestor module.
        ///
        /// - Parameter levels: How many `super`s to climb.
        /// - Returns: The ancestor, or the crate root if the climb goes past it.
        func up(_ levels: Int) -> Module {
            Module(base: base, path: Array(path.dropLast(levels)))
        }
    }

    /// Where a `use` path starts: a module, the segments still to follow, and whether the module is in the
    /// importer's own crate.
    private struct PathStart {
        let module: Module
        let rest: ArraySlice<String>
        let isOwnCrate: Bool
    }

    /// Creates the resolver over the project's files and workspace.
    ///
    /// - Parameters:
    ///   - paths: Every indexed file's repo-relative path.
    ///   - repoRoot: The repository root, for `Cargo.toml`.
    init(paths: Set<String>, repoRoot: URL) {
        self.paths = paths
        workspace = CargoWorkspace(paths: paths, repoRoot: repoRoot).libraries
    }

    /// The node for a Rust file: the file itself.
    ///
    /// - Parameter path: The file's repo-relative path.
    /// - Returns: The path.
    func node(of path: String) -> String { path }

    /// Resolves a crate root's `mod` declaration or any `use` path, as `RustModuleFacts` records them.
    ///
    /// - Parameters:
    ///   - specifier: `mod name`, or a `use` path such as `crate::a::b`.
    ///   - path: The declaring file.
    /// - Returns: The module's file, or `nil` for a nested module's `mod`, the standard library, an external crate,
    ///   or an ancestor.
    func resolve(_ specifier: String, from path: String) -> String? {
        let current = module(of: path)
        guard specifier.hasPrefix("mod ") else { return usedFile(segments(Substring(specifier)), from: current) }
        return current.path.isEmpty ? declaredFile(specifier.dropFirst("mod ".count), in: path) : nil
    }

    /// Finds the file a `mod name;` declaration loads, from any module: `name.rs` or `name/mod.rs` beside a crate
    /// root or `mod.rs`, and under `a/` for a declaration in `a.rs`.
    ///
    /// - Parameters:
    ///   - name: The declared module, with any inline modules around it, as `outer::name`.
    ///   - path: The declaring file.
    /// - Returns: The module's file, or `nil` if it isn't indexed.
    func declaredFile(_ name: Substring, in path: String) -> String? {
        let current = module(of: path)
        return file(of: Module(base: current.base, path: current.path + segments(name)))
    }

    /// Resolves a `use` path from a module.
    ///
    /// - Parameters:
    ///   - parts: The path's segments.
    ///   - current: The importing file's module.
    /// - Returns: The file of the deepest module the path names, unless it's the importer's own ancestor.
    private func usedFile(_ parts: [String], from current: Module) -> String? {
        guard let first = parts.first, let start = start(first, parts.dropFirst(), from: current) else { return nil }
        var target = start.module
        for part in start.rest where part != "self" {
            let deeper = Module(base: target.base, path: target.path + [part])
            guard file(of: deeper) != nil else { break }
            target = deeper
        }
        if start.isOwnCrate, current.path.starts(with: target.path) { return nil }
        return file(of: target) ?? (target.path.isEmpty ? workspaceRoot(of: target) : nil)
    }

    /// Finds the module a `use` path starts from, from its leading `crate`, `self`, `super`, or crate name.
    ///
    /// - Parameters:
    ///   - first: The first segment.
    ///   - rest: The segments after it.
    ///   - current: The importing file's module.
    /// - Returns: Where the path starts, or `nil` for a path outside the project.
    private func start(_ first: String, _ rest: ArraySlice<String>, from current: Module) -> PathStart? {
        switch first {
        case "crate": PathStart(module: Module(base: current.base, path: []), rest: rest, isOwnCrate: true)
        case "self": PathStart(module: current, rest: rest, isOwnCrate: true)
        case Self.superSegment:
            PathStart(module: current.up(1 + rest.prefix { $0 == Self.superSegment }.count),
                      rest: rest.drop { $0 == Self.superSegment }, isOwnCrate: true)
        default: childOrCrate(first, rest, from: current)
        }
    }

    /// Starts a path at a child module of the current one, or else at another workspace crate's root.
    ///
    /// - Parameters:
    ///   - first: The first segment, a module or crate name.
    ///   - rest: The segments after it.
    ///   - current: The importing file's module.
    /// - Returns: Where the path starts, or `nil` for an external crate.
    private func childOrCrate(_ first: String, _ rest: ArraySlice<String>, from current: Module) -> PathStart? {
        let child = Module(base: current.base, path: current.path + [first])
        if file(of: child) != nil { return PathStart(module: child, rest: rest, isOwnCrate: true) }
        return workspace[first].map { PathStart(module: module(of: $0), rest: rest, isOwnCrate: false) }
    }

    /// Finds the library root file of another crate's root module.
    ///
    /// - Parameter module: A crate's root module.
    /// - Returns: The workspace library whose source folder it is.
    private func workspaceRoot(of module: Module) -> String? {
        workspace.values.sorted().first { ProjectPath.directory(of: $0) == module.base }
    }

    /// Finds a module's file.
    ///
    /// - Parameter module: The module.
    /// - Returns: `a/b.rs` or `a/b/mod.rs` under its crate folder, or `nil` for the crate root or a missing file.
    private func file(of module: Module) -> String? {
        guard !module.path.isEmpty else { return nil }
        let stem = ([module.base].filter { !$0.isEmpty } + module.path).joined(separator: "/")
        return [stem + ".rs", stem + "/mod.rs"].first(where: paths.contains)
    }

    /// Works out a file's module: its crate's source folder, and the module path below it.
    ///
    /// - Parameter path: A repo-relative `.rs` path.
    /// - Returns: The file's module; a crate root's path is empty.
    private func module(of path: String) -> Module {
        let directory = ProjectPath.directory(of: path), name = (path as NSString).lastPathComponent
        if isCrateRoot(name: name, directory: directory) { return Module(base: directory, path: []) }
        var base = directory, below: [String] = []
        while !base.isEmpty, !isSourceFolder(base) {
            below.insert((base as NSString).lastPathComponent, at: 0)
            base = ProjectPath.directory(of: base)
        }
        let stem = (name as NSString).deletingPathExtension
        return Module(base: base, path: below + (stem == "mod" ? [] : [stem]))
    }

    /// Reports whether a file is a crate root: `lib.rs`, `main.rs`, `build.rs`, or any file directly in `src/bin` or
    /// a package's `tests`, `examples`, or `benches` folder.
    ///
    /// - Parameters:
    ///   - name: The file name.
    ///   - directory: Its folder.
    /// - Returns: Whether it's a crate root.
    private func isCrateRoot(name: String, directory: String) -> Bool {
        Self.rootFileNames.contains(name) || isRootFolder(directory)
    }

    /// Reports whether a folder's files are each a crate root: `src/bin`, or a package's `tests`, `examples`, or
    /// `benches` folder.
    ///
    /// - Parameter directory: A repo-relative folder.
    /// - Returns: Whether it's a folder of crate roots.
    private func isRootFolder(_ directory: String) -> Bool {
        let parts = directory.split(separator: "/").map(String.init)
        guard let last = parts.last else { return false }
        if last == "bin" { return parts.dropLast().last == "src" }
        return Self.rootFolders.contains(last) && !parts.dropLast().contains("src")
    }

    /// Reports whether a folder is a crate's source folder: it holds a `lib.rs` or `main.rs`, or it's a folder of
    /// crate roots.
    ///
    /// - Parameter directory: A repo-relative folder.
    /// - Returns: Whether module paths start there.
    private func isSourceFolder(_ directory: String) -> Bool {
        isRootFolder(directory) || paths.contains(directory + "/lib.rs") || paths.contains(directory + "/main.rs")
    }

    /// Splits a path on `::`.
    ///
    /// - Parameter path: A Rust path, such as `crate::a::b`.
    /// - Returns: Its segments.
    private func segments(_ path: Substring) -> [String] {
        path.components(separatedBy: "::").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
