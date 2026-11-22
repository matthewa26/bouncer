import Foundation

/// The files whose changes can change other files' per-file findings, and the files they can affect.
///
/// A few per-file rules look at files around the one they check: whether a Swift file belongs to an executable
/// target depends on `Package.swift` and on a `main.swift` or `@main` file in a directory above it
/// (`SwiftTargetKind`), and whether a Rust file is a program depends on the `Cargo.toml` above it and on
/// `src/main.rs` and `src/lib.rs` (`RustCrateLayout`). Each of those files lives in a directory at or above
/// the files it affects, so when one changes, appears, or vanishes, every file under its directory is analyzed
/// again rather than reused.
enum NeighborFiles {
    /// File names whose presence or contents other files' findings depend on.
    private static let names: Set<String> = ["Package.swift", "Cargo.toml", "main.swift", "main.rs", "lib.rs"]
    /// The marker of a Swift entry point; matching it anywhere errs on the side of re-analyzing.
    private static let entryPointMarker = "@main"
    private static let swiftExtension = ".swift"

    /// Reports whether a change to a file can change the findings of files under its directory.
    ///
    /// - Parameters:
    ///   - path: The file's repo-relative path.
    ///   - contents: Its contents.
    /// - Returns: Whether it's a manifest, an entry point, or a Swift file declaring `@main`.
    static func affectsNeighbors(path: String, contents: String) -> Bool {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        if names.contains(name) { return true }
        return name.hasSuffix(swiftExtension) && contents.contains(entryPointMarker)
    }

    /// The directory a file's changes reach: its own, as a repo-relative path, `""` for the repo root.
    ///
    /// - Parameter path: The file's repo-relative path.
    /// - Returns: Its directory.
    static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    /// Reports whether a file lies under any of the given directories.
    ///
    /// - Parameters:
    ///   - path: The file's repo-relative path.
    ///   - directories: Repo-relative directories, `""` for the root.
    /// - Returns: Whether one of its ancestor directories is listed.
    static func isUnder(_ path: String, anyOf directories: Set<String>) -> Bool {
        var directory = path
        while !directory.isEmpty {
            directory = self.directory(of: directory)
            if directories.contains(directory) { return true }
        }
        return false
    }
}
