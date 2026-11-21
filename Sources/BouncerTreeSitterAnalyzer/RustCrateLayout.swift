import Foundation

/// Where a Rust file sits in its Cargo package, which decides whether it's test code or part of a program.
///
/// The package is the nearest directory above the file (inside the repository) holding a `Cargo.toml`. Without
/// one on disk, it's the directory above the file's nearest `src`, `tests`, `benches`, or `examples` folder.
struct RustCrateLayout {
    /// Folders whose files are tests, benchmarks, or examples rather than library code.
    private static let testFolders: Set<String> = ["tests", "benches", "examples"]
    private static let layoutFolders = testFolders.union(["src"])
    private static let maxLevels = 8

    /// The file's path components below its package directory, such as `["src", "bin", "tool.rs"]`.
    let components: [String]
    /// Whether the package builds only a program: it has `src/main.rs` and no `src/lib.rs`.
    let isBinaryPackage: Bool

    /// Works out a file's place in its package.
    ///
    /// - Parameters:
    ///   - file: The file's location.
    ///   - repoRoot: The repository root, which the search for `Cargo.toml` doesn't climb above.
    init(file: URL, repoRoot: URL) {
        let package = Self.manifestDirectory(of: file, repoRoot: repoRoot) ?? Self.layoutDirectory(of: file)
        let all = file.standardizedFileURL.pathComponents, base = package.standardizedFileURL.pathComponents
        components = Array(all.dropFirst(base.count))
        let manager = FileManager.default, source = package.appendingPathComponent("src")
        isBinaryPackage = manager.fileExists(atPath: source.appendingPathComponent("main.rs").path)
            && !manager.fileExists(atPath: source.appendingPathComponent("lib.rs").path)
    }

    /// Whether the file is test code by where it is: an integration test, benchmark, or example; a module under a
    /// `tests` folder (`src/tests/util.rs`, declared from `#[cfg(test)] mod tests;`); or a `tests.rs` module.
    var isTestFile: Bool {
        if components.first.map(Self.testFolders.contains) ?? false { return true }
        return components.dropLast().contains("tests") || components.last == "tests.rs"
    }

    /// Whether the file is part of a program, where printing and panicking are expected: a build script, a binary
    /// entry point (any `main.rs`, `src/bin/…`), an example, or any source file of a package with no library.
    var isProgram: Bool {
        if components == ["build.rs"] || components.last == "main.rs" { return true }
        if components.starts(with: ["src", "bin"]) || components.first == "examples" { return true }
        return isBinaryPackage && components.first == "src"
    }

    /// Finds the nearest directory above a file that holds a `Cargo.toml`, without leaving the repository.
    ///
    /// - Parameters:
    ///   - file: The file's location.
    ///   - repoRoot: The repository root.
    /// - Returns: The package directory, or `nil` if none is found.
    private static func manifestDirectory(of file: URL, repoRoot: URL) -> URL? {
        var directory = file.deletingLastPathComponent().standardizedFileURL
        let root = repoRoot.standardizedFileURL.path
        for _ in 0..<maxLevels where directory.path.hasPrefix(root) {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Cargo.toml").path) {
                return directory
            }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }

    /// Guesses a file's package directory from its path: the one above its nearest layout folder.
    ///
    /// - Parameter file: The file's location.
    /// - Returns: The directory above the nearest `src`, `tests`, `benches`, or `examples`, else the file's own.
    private static func layoutDirectory(of file: URL) -> URL {
        let directories = Array(file.deletingLastPathComponent().standardizedFileURL.pathComponents)
        guard let index = directories.lastIndex(where: layoutFolders.contains) else {
            return file.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(directories[..<index])))
    }
}
