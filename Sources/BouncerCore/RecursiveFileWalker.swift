import Foundation

/// Supplies every file under a directory, for `bouncer review`'s ad-hoc audit mode.
///
/// Skips a small set of conventionally-noisy directories (`.git`,
/// `node_modules`, build output) plus anything matching a configured exclude
/// glob. This isn't a full `.gitignore` engine, just a practical default. Hidden files and folders are
/// skipped too, except the CI workflows and actions inside a `.github` folder, which only the rules in
/// `HiddenCIFiles` report in.
public struct RecursiveFileWalker: TargetFileProvider {
    private static let alwaysSkippedDirectories: Set<String> = [
        ".git", "node_modules", ".build", "dist", "build", ".venv", "__pycache__", ".git-baseline"
    ]

    private let rootDirectory: URL
    private let excludeFilter: ExcludeFilter

    /// Creates a recursive file walker.
    ///
    /// - Parameters:
    ///   - rootDirectory: The directory to walk.
    ///   - excludeGlobs: Glob patterns, relative to `rootDirectory`, to exclude.
    public init(rootDirectory: URL, excludeGlobs: [String] = []) {
        self.rootDirectory = rootDirectory
        self.excludeFilter = ExcludeFilter(root: rootDirectory, globs: excludeGlobs)
    }

    /// Walks the directory tree and returns every non-excluded regular file.
    ///
    /// - Returns: The matched files' absolute locations.
    /// - Throws: Never, but conforms to `TargetFileProvider`'s throwing signature.
    public func targetFiles() throws -> [URL] {
        guard isDirectory(rootDirectory) else { return excludeFilter.excludes(rootDirectory) ? [] : [rootDirectory] }
        var results: [URL] = []
        walk(rootDirectory, into: &results)
        return results
    }

    /// Lists one directory and recurses into the subdirectories the walk keeps.
    ///
    /// The walk recurses itself rather than using `FileManager`'s enumerator with `skipDescendants()`: on
    /// Windows, Foundation's enumerator applies a skip to a different directory than the one just listed,
    /// so skipping `.hidden` could drop `.github` or `src` instead. It lists names by path, because on
    /// Windows the URL-based listing fails for a whole directory that holds one broken symlink.
    ///
    /// - Parameters:
    ///   - directory: The directory to list.
    ///   - results: The accumulated matching files.
    private func walk(_ directory: URL, into results: inout [URL]) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names {
            visit(directory.appendingPathComponent(name), results: &results)
        }
    }

    /// Handles one listed path: skips noisy and hidden directories, walks into the rest, and collects
    /// matching files.
    ///
    /// - Parameters:
    ///   - url: The listed path.
    ///   - results: The accumulated matching files.
    private func visit(_ url: URL, results: inout [URL]) {
        if isAlwaysSkippedDirectory(url) || isSkippedHidden(url) { return }
        if isDirectory(url) {
            // Links to folders aren't followed, so a link can't walk out of the root or loop.
            if !isSymbolicLink(url) { walk(url, into: &results) }
            return
        }
        if isListedFile(url) { results.append(url) }
    }

    /// Checks whether the walk would list a file, for a provider that finds candidate files some other way,
    /// such as from git, and must leave out exactly what the walk does: files in skipped or hidden folders,
    /// hidden files, excluded files, and files in a `.github` folder that aren't CI files.
    ///
    /// - Parameter url: A candidate file, expressed under the walk's root (not resolved through symlinks).
    /// - Returns: Whether the file lies under the root and the walk would list it.
    public func admits(_ url: URL) -> Bool {
        let base = rootDirectory.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.starts(with: base) else { return false }
        var current = rootDirectory
        for name in components.dropFirst(base.count) {
            current.appendPathComponent(name)
            if isAlwaysSkippedDirectory(current) || isSkippedHidden(current) { return false }
        }
        return isListedFile(url)
    }

    /// Checks the walk's per-file conditions: an existing, non-excluded file that, inside a `.github` folder,
    /// is a CI file.
    ///
    /// - Parameter url: The file to check.
    /// - Returns: Whether the walk lists the file once it reaches it.
    private func isListedFile(_ url: URL) -> Bool {
        isReadableFile(url) && !excludeFilter.excludes(url) && isListedIfInsideCIFolder(url)
    }

    /// Limits rules in a walked `.github` CI file to the supply-chain rules.
    ///
    /// - Parameter url: One of the walked files.
    /// - Returns: `HiddenCIFiles.ruleIDs` for a file inside a `.github` folder, otherwise `nil`.
    public func ruleScope(for url: URL) -> Set<String>? {
        HiddenCIFiles.isInside(relativeComponents(of: url)) ? HiddenCIFiles.ruleIDs : nil
    }

    /// Checks whether a path is hidden (its name starts with a dot) and isn't a `.github` folder.
    ///
    /// - Parameter url: The enumerated path.
    /// - Returns: Whether the walk leaves it out, with everything inside it.
    private func isSkippedHidden(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix(".") && !(name == HiddenCIFiles.folder && isDirectory(url))
    }

    /// Checks that a file inside a `.github` folder is a workflow or action; any other file passes.
    ///
    /// - Parameter url: The enumerated file.
    /// - Returns: Whether the file may be listed.
    private func isListedIfInsideCIFolder(_ url: URL) -> Bool {
        let components = relativeComponents(of: url)
        return !HiddenCIFiles.isInside(components) || HiddenCIFiles.isCIFile(components)
    }

    /// Splits a walked path into its components below the walk's root, matching the root with or without
    /// its symlinks resolved, since the enumerator may report either form. Paths without a `.github`
    /// folder anywhere return early, so the common case costs no file-system lookups.
    ///
    /// - Parameter url: A path under the root.
    /// - Returns: Its components below the root, or none if it isn't under it or has no `.github` folder.
    private func relativeComponents(of url: URL) -> [String] {
        guard url.path.contains("/\(HiddenCIFiles.folder)/") else { return [] }
        let file = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let base = rootDirectory.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard file.starts(with: base) else { return [] }
        return Array(file.dropFirst(base.count))
    }

    /// Checks whether a path leads to a file, following symlinks, so links to directories (which the
    /// enumerator doesn't descend into) and broken links aren't collected as files.
    ///
    /// - Parameter url: The enumerated path.
    /// - Returns: Whether the path, or its symlink target, is an existing non-directory.
    private func isReadableFile(_ url: URL) -> Bool {
        var targetIsDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &targetIsDirectory)
        return exists && !targetIsDirectory.boolValue
    }

    /// Checks whether a path is one of the conventionally-skipped directories.
    ///
    /// - Parameter url: The path to check.
    /// - Returns: Whether the path is a directory Bouncer never walks into.
    private func isAlwaysSkippedDirectory(_ url: URL) -> Bool {
        isDirectory(url) && Self.alwaysSkippedDirectories.contains(url.lastPathComponent)
    }

    /// Checks whether a path is itself a symbolic link, without following it.
    ///
    /// - Parameter url: The path to check.
    /// - Returns: Whether the path is a symbolic link.
    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
    }

    /// Checks whether a path is a directory.
    ///
    /// - Parameter url: The path to check.
    /// - Returns: Whether the path is a directory.
    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
}
