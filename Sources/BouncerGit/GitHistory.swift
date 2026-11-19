import Foundation

/// One file's change within a commit or a diff, as `git --numstat` reports it.
public struct GitFileChange: Sendable, Equatable {
    /// The repo-relative path after the change, with `/` separators.
    public let path: String
    /// The path before a rename, or `nil` when the file kept its name.
    public let oldPath: String?
    /// Lines added, or `nil` for a binary file.
    public let added: Int?
    /// Lines deleted, or `nil` for a binary file.
    public let deleted: Int?

    /// Creates a file change.
    ///
    /// - Parameters:
    ///   - path: The path after the change.
    ///   - oldPath: The path before a rename, if renamed.
    ///   - added: Lines added, or `nil` for a binary file.
    ///   - deleted: Lines deleted, or `nil` for a binary file.
    public init(path: String, oldPath: String? = nil, added: Int?, deleted: Int?) {
        self.path = path
        self.oldPath = oldPath
        self.added = added
        self.deleted = deleted
    }

    /// Lines added plus lines deleted; 0 for a binary file.
    public var changedLines: Int { (added ?? 0) + (deleted ?? 0) }

    /// Returns a copy at a different path, keeping its rename source and line counts.
    ///
    /// - Parameter newPath: The path to report the change under.
    /// - Returns: The same change at `newPath`.
    func moved(to newPath: String) -> GitFileChange {
        GitFileChange(path: newPath, oldPath: oldPath, added: added, deleted: deleted)
    }
}

/// One non-merge commit: who made it, when, and which files it changed.
public struct GitCommit: Sendable, Equatable {
    public let hash: String
    /// The author's email as `.mailmap` maps it, lowercased.
    public let author: String
    /// The commit (committer) date.
    public let date: Date
    public let changes: [GitFileChange]

    /// Creates a commit.
    ///
    /// - Parameters:
    ///   - hash: The commit's full hash.
    ///   - author: The author's normalized email.
    ///   - date: The commit date.
    ///   - changes: The files it changed.
    public init(hash: String, author: String, date: Date, changes: [GitFileChange]) {
        self.hash = hash
        self.author = author
        self.date = date
        self.changes = changes
    }
}

/// Parses the output of `git log --numstat` and `git diff --numstat` in the formats `GitHistoryReader` asks for.
public enum GitLogParser {
    /// Separates commits in the log; written by `%x1e` at the start of each commit's header.
    static let recordSeparator: Character = "\u{1E}"
    /// Separates the header's fields; written by `%x1f`.
    static let fieldSeparator: Character = "\u{1F}"
    /// The `--format` that produces headers this parser reads: hash, mailmapped author email, commit time.
    static let format = "--format=%x1e%H%x1f%aE%x1f%ct"

    /// Parses a whole log, newest commit first as git writes it.
    ///
    /// - Parameter output: The output of `git log --numstat` with `format`.
    /// - Returns: The commits, skipping any record whose header doesn't parse.
    public static func commits(from output: String) -> [GitCommit] {
        output.split(separator: recordSeparator).compactMap { commit(from: $0) }
    }

    /// Parses `--numstat` lines into file changes.
    ///
    /// - Parameter output: Lines of `added<TAB>deleted<TAB>path`, as from `git diff --numstat`.
    /// - Returns: The changes, skipping lines that don't parse.
    public static func changes(from output: Substring) -> [GitFileChange] {
        output.split(whereSeparator: \.isNewline).compactMap { change(from: $0) }
    }

    /// Parses one commit's record: its header line, then its numstat lines.
    ///
    /// - Parameter record: The text between two record separators.
    /// - Returns: The commit, or `nil` if the header is malformed.
    private static func commit(from record: Substring) -> GitCommit? {
        let lines = record.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let fields = lines.first?.split(separator: fieldSeparator, omittingEmptySubsequences: false) ?? []
        guard fields.count == 3, let seconds = TimeInterval(fields[2].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        let date = Date(timeIntervalSince1970: seconds), changes = lines.count > 1 ? Self.changes(from: lines[1]) : []
        return GitCommit(hash: String(fields[0]), author: fields[1].lowercased(), date: date, changes: changes)
    }

    /// Parses one numstat line, including the rename forms `old => new` and `dir/{old => new}/file`.
    ///
    /// - Parameter line: `added<TAB>deleted<TAB>path`, with `-` counts for a binary file.
    /// - Returns: The change, or `nil` if the line isn't numstat.
    static func change(from line: Substring) -> GitFileChange? {
        let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count == 3, !fields[2].isEmpty else { return nil }
        let added = Int(fields[0]), deleted = Int(fields[1])
        guard added != nil || fields[0] == "-", deleted != nil || fields[1] == "-" else { return nil }
        let (oldPath, path) = renamePaths(String(fields[2]))
        return GitFileChange(path: path, oldPath: oldPath, added: added, deleted: deleted)
    }

    /// Splits a numstat path into the old and new paths of a rename.
    ///
    /// - Parameter text: The path as numstat writes it.
    /// - Returns: The old path (`nil` without a rename) and the new path.
    static func renamePaths(_ text: String) -> (old: String?, new: String) {
        guard let arrow = text.range(of: " => ") else { return (nil, text) }
        guard let open = text[..<arrow.lowerBound].lastIndex(of: "{"),
              let close = text[arrow.upperBound...].firstIndex(of: "}") else {
            return (String(text[..<arrow.lowerBound]), String(text[arrow.upperBound...]))
        }
        let prefix = text[..<open], suffix = text[text.index(after: close)...]
        let old = String(prefix + text[text.index(after: open)..<arrow.lowerBound] + suffix)
        let new = String(prefix + text[arrow.upperBound..<close] + suffix)
        return (collapseSlashes(old), collapseSlashes(new))
    }

    /// Removes the doubled or leading `/` a brace rename leaves when one side is empty, as in `a/{ => b}/c`.
    ///
    /// - Parameter path: The reassembled path.
    /// - Returns: The path with single separators.
    private static func collapseSlashes(_ path: String) -> String {
        String(path.replacingOccurrences(of: "//", with: "/").drop { $0 == "/" })
    }
}

/// Rewrites a history so every change is filed under the path its file has today.
enum RenameFollower {
    /// Follows renames from newest to oldest commit, mapping each old path to the file's current path.
    ///
    /// - Parameter commits: The commits, newest first.
    /// - Returns: The same commits with renamed files' older changes under their current paths.
    static func follow(_ commits: [GitCommit]) -> [GitCommit] {
        var current: [String: String] = [:]
        return commits.map { commit in
            let changes = commit.changes.map { refile($0, current: &current) }
            return GitCommit(hash: commit.hash, author: commit.author, date: commit.date, changes: changes)
        }
    }

    /// Files one change under its current path, and remembers a rename's old path for older commits.
    ///
    /// - Parameters:
    ///   - change: The change, as its commit recorded it.
    ///   - current: Each old path's current path, from the newer commits already seen.
    /// - Returns: The change under its current path.
    private static func refile(_ change: GitFileChange, current: inout [String: String]) -> GitFileChange {
        let path = current[change.path] ?? change.path
        if let old = change.oldPath, old != change.path { current[old] = path }
        return change.moved(to: path)
    }
}
