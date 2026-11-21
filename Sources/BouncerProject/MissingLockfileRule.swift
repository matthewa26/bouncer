import Foundation
import BouncerCore

/// Flags a manifest whose installs aren't reproducible because no lockfile is committed beside it, reported
/// at its line 1.
///
/// - `package.json` with `dependencies`, `devDependencies`, or `optionalDependencies` and no
///   `package-lock.json`, `npm-shrinkwrap.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lockb`, or `bun.lock` in
///   its folder or any folder above it in the repository, where a workspace root keeps it.
/// - `Cargo.toml` for a binary crate (`[[bin]]`, or `src/main.rs` beside it) or a workspace root
///   (`[workspace]`) with no `Cargo.lock` in its folder or above. Libraries conventionally leave theirs out.
/// - The root `Package.swift` with remote dependencies and no `Package.resolved`, only with the
///   `swiftPackages` parameter set, since libraries often leave it out too.
///
/// Manifests are found among the files being checked, so an excluded manifest isn't reported.
public struct MissingLockfileRule: ProjectRule {
    public let id = "missing-lockfile"
    private static let swiftManifest = "Package.swift"

    /// Creates the rule.
    public init() {}

    /// Checks every `package.json`, `Cargo.toml`, and (when `swiftPackages` is set) root `Package.swift` being
    /// checked.
    ///
    /// - Parameters:
    ///   - index: The project's facts, used to read manifests.
    ///   - targets: The repo-relative paths being checked.
    ///   - context: Repo-wide state, with `swiftPackages` (false).
    /// - Returns: One finding per manifest without a lockfile.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let swift = context.settings(for: id).parameters.bool("swiftPackages", default: false)
        let disk = LockfileDisk(files: ManifestFiles(index: index, repoRoot: context.repoRoot))
        return targets.filter { swift || $0 != Self.swiftManifest }.sorted().compactMap { path in
            message(for: path, disk: disk).map { ProjectFinding.make(id, path, 1, $0, context) }
        }
    }

    /// Explains a manifest's missing lockfile.
    ///
    /// - Parameters:
    ///   - path: A target's repo-relative path.
    ///   - disk: Reads manifests and looks for lockfiles.
    /// - Returns: The message, or `nil` if the file isn't a manifest missing its lockfile.
    private func message(for path: String, disk: LockfileDisk) -> String? {
        switch (path as NSString).lastPathComponent {
        case "package.json": return npm(path, disk: disk)
        case "Cargo.toml": return cargo(path, disk: disk)
        case Self.swiftManifest where path == Self.swiftManifest: return swiftPackage(path, disk: disk)
        default: return nil
        }
    }

    /// Checks a `package.json` with dependencies for a lockfile at or above its folder.
    ///
    /// - Parameters:
    ///   - path: The manifest.
    ///   - disk: Reads it and looks for lockfiles.
    /// - Returns: The message, or `nil` if it has no dependencies or has a lockfile.
    private func npm(_ path: String, disk: LockfileDisk) -> String? {
        guard let text = disk.read(path),
              let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              NPMSections.all.contains(where: { !(json[$0] as? [String: Any] ?? [:]).isEmpty }),
              !disk.hasAny(NPMSections.lockfiles, atOrAbove: path) else { return nil }
        return "This package declares dependencies but no lockfile (package-lock.json, pnpm-lock.yaml, yarn.lock, "
            + "or bun.lock) is committed here or at a workspace root; commit one so installs are reproducible."
    }

    /// Checks a binary crate's or workspace root's `Cargo.toml` for a `Cargo.lock` at or above its folder.
    ///
    /// - Parameters:
    ///   - path: The manifest.
    ///   - disk: Reads it and looks for lockfiles.
    /// - Returns: The message, or `nil` for a library or a crate with a lockfile.
    private func cargo(_ path: String, disk: LockfileDisk) -> String? {
        guard let text = disk.read(path), !disk.hasAny(["Cargo.lock"], atOrAbove: path) else { return nil }
        let headers = Set(text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        let isWorkspace = headers.contains("[workspace]")
        let isBinary = headers.contains("[[bin]]") || disk.exists(path, sibling: "src/main.rs")
        guard isWorkspace || isBinary else { return nil }
        let kind = isWorkspace ? "This workspace" : "This binary crate"
        return kind + " has no Cargo.lock; commit it so builds use the dependency versions you tested."
    }

    /// Checks the root `Package.swift` with remote dependencies for a `Package.resolved` beside it.
    ///
    /// - Parameters:
    ///   - path: The manifest.
    ///   - disk: Reads it and looks for `Package.resolved`.
    /// - Returns: The message, or `nil` without remote dependencies or with a `Package.resolved`.
    private func swiftPackage(_ path: String, disk: LockfileDisk) -> String? {
        guard let text = disk.read(path), text.contains(".package(url:") || text.contains(".package(id:"),
              !disk.exists(path, sibling: "Package.resolved") else { return nil }
        return "This package has remote dependencies but no Package.resolved; commit it so builds resolve the "
            + "versions you tested."
    }
}

/// The `package.json` sections whose packages a lockfile pins, and the lockfiles npm, pnpm, Yarn, and Bun write.
enum NPMSections {
    static let all = ["dependencies", "devDependencies", "optionalDependencies"]
    static let lockfiles = [
        "package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml", "yarn.lock", "bun.lockb", "bun.lock"
    ]
}

/// Reads manifests and looks for lockfiles on disk, within the repository.
struct LockfileDisk {
    let files: ManifestFiles

    /// Reads a manifest.
    ///
    /// - Parameter path: Its repo-relative path.
    /// - Returns: Its text, or `nil` if it can't be read.
    func read(_ path: String) -> String? {
        files.read(path)
    }

    /// Reports whether a file exists relative to a manifest's folder.
    ///
    /// - Parameters:
    ///   - manifest: The manifest's repo-relative path.
    ///   - sibling: The path relative to its folder, such as `src/main.rs`.
    /// - Returns: Whether it exists.
    func exists(_ manifest: String, sibling: String) -> Bool {
        exists(sibling, in: ProjectPath.directory(of: manifest))
    }

    /// Reports whether any of the named files is in a manifest's folder or a folder above it, up to the root.
    ///
    /// - Parameters:
    ///   - names: The lockfile names.
    ///   - manifest: The manifest's repo-relative path.
    /// - Returns: Whether one exists.
    func hasAny(_ names: [String], atOrAbove manifest: String) -> Bool {
        var folder = ProjectPath.directory(of: manifest)
        while true {
            let current = folder
            if names.contains(where: { exists($0, in: current) }) { return true }
            if folder.isEmpty { return false }
            folder = ProjectPath.directory(of: folder)
        }
    }

    /// Reports whether a file exists in a folder.
    ///
    /// - Parameters:
    ///   - name: The file's path relative to the folder.
    ///   - folder: The repo-relative folder, `""` for the root.
    /// - Returns: Whether it exists.
    private func exists(_ name: String, in folder: String) -> Bool {
        let path = folder.isEmpty ? name : folder + "/" + name
        return FileManager.default.fileExists(atPath: RepoPath.url(path, in: files.repoRoot).path)
    }
}
