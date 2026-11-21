import Foundation
import BouncerCore

/// The few `Cargo.toml` values the Rust resolver needs, read line by line without a TOML library.
///
/// It understands `[section]` headers, `key = "string"` (or `'string'`) values, and string arrays on one line or
/// spread over several (`members = [` … `]`), with `#` comments outside strings. Anything else (inline tables,
/// dotted keys such as `name.workspace = true`, multi-line strings) is skipped.
struct CargoManifest {
    /// Each section's keys and their string values; a plain string is a one-element list.
    private var sections: [String: [String: [String]]] = [:]
    /// The section the reader is in.
    private var section = ""
    /// An array value spread over several lines, still open.
    private var pending: (key: String, values: [String])?
    /// A double- or single-quoted string, capturing its contents.
    private static let quoted = try? NSRegularExpression(pattern: #""([^"]*)"|'([^']*)'"#)
    /// The part of a line before any `#` that isn't inside a string.
    private static let beforeComment = try? NSRegularExpression(pattern: #"^(?:[^"'#]|"[^"]*"|'[^']*')*"#)

    /// Reads a manifest's text.
    ///
    /// - Parameter text: The `Cargo.toml` contents.
    init(text: String) {
        for raw in text.split(whereSeparator: \.isNewline) {
            read(line: Self.stripComment(raw).trimmingCharacters(in: .whitespaces))
        }
    }

    /// Reads one trimmed line: more of an open array, a section header, or an assignment.
    ///
    /// - Parameter line: The line, without its comment.
    private mutating func read(line: String) {
        if let open = pending {
            extend(open, with: line)
        } else if line.hasPrefix("[") {
            section = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        } else if let (key, value) = Self.assignment(line) {
            let values = Self.strings(in: value)
            if value.hasPrefix("["), !value.contains("]") { pending = (key, values) } else { store(key, values) }
        }
    }

    /// Adds a line's strings to an open array, storing it once the line closes it.
    ///
    /// - Parameters:
    ///   - open: The array so far.
    ///   - line: The next line.
    private mutating func extend(_ open: (key: String, values: [String]), with line: String) {
        let values = open.values + Self.strings(in: line)
        pending = line.contains("]") ? nil : (open.key, values)
        if pending == nil { store(open.key, values) }
    }

    /// Stores a key's values in the current section.
    ///
    /// - Parameters:
    ///   - key: The key.
    ///   - values: Its strings.
    private mutating func store(_ key: String, _ values: [String]) {
        sections[section, default: [:]][key] = values
    }

    /// Reads the manifest at a repo-relative path.
    ///
    /// - Parameters:
    ///   - path: The manifest's path, such as `crates/core/Cargo.toml`.
    ///   - repoRoot: The repository root.
    /// - Returns: The manifest, or `nil` if it can't be read.
    static func read(_ path: String, repoRoot: URL) -> CargoManifest? {
        let url = repoRoot.appendingPathComponent(path)
        return (try? String(contentsOf: url, encoding: .utf8)).map(CargoManifest.init(text:))
    }

    /// Looks up one value.
    ///
    /// - Parameters:
    ///   - key: The key, such as `name`.
    ///   - section: The section, such as `package`.
    /// - Returns: The key's strings, empty if it isn't set.
    func values(_ key: String, in section: String) -> [String] {
        sections[section]?[key] ?? []
    }

    /// Splits a `key = value` line.
    ///
    /// - Parameter line: A trimmed line.
    /// - Returns: The key and the trimmed value, or `nil` if the line isn't an assignment.
    private static func assignment(_ line: String) -> (String, String)? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || "_-".contains($0) }) else { return nil }
        return (key, line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces))
    }

    /// Lists the quoted strings in a piece of a line.
    ///
    /// - Parameter text: The text.
    /// - Returns: Each `"…"` or `'…'` string's contents, in order.
    private static func strings(in text: String) -> [String] {
        let matches = quoted?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        return matches.compactMap { match in
            [1, 2].compactMap { Range(match.range(at: $0), in: text) }.first.map { String(text[$0]) }
        }
    }

    /// Drops a `#` comment, unless the `#` is inside a string.
    ///
    /// - Parameter line: A raw line.
    /// - Returns: The line up to its first `#` outside quotes.
    private static func stripComment(_ line: Substring) -> String {
        let text = String(line)
        guard let match = beforeComment?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return text }
        return String(text[range])
    }
}

/// The repository's own crates: the root package and every `[workspace] members` entry (globs such as `crates/*`
/// included) whose library source is indexed, keyed by the name other crates `use` it by.
struct CargoWorkspace {
    /// Each crate's name (its `[lib] name`, else its package name with `-` as `_`) and library root file.
    let libraries: [String: String]
    /// Where a package keeps its library crate's root, unless `[lib] path` says otherwise.
    private static let libraryRoot = "src/lib.rs"

    /// Reads the root `Cargo.toml` and each member's.
    ///
    /// - Parameters:
    ///   - paths: Every indexed file's repo-relative path.
    ///   - repoRoot: The repository root.
    init(paths: Set<String>, repoRoot: URL) {
        let members = CargoManifest.read("Cargo.toml", repoRoot: repoRoot)?.values("members", in: "workspace")
        let packages = members.map { Self.packages(in: paths, members: $0) } ?? []
        let named = packages.compactMap { Self.library(in: $0, paths: paths, repoRoot: repoRoot) }
        libraries = Dictionary(named) { first, _ in first }
    }

    /// Lists the packages with an indexed library: the root one and each workspace member.
    ///
    /// - Parameters:
    ///   - paths: Every indexed file's path.
    ///   - members: The `[workspace] members` entries, which may be globs.
    /// - Returns: The package folders, sorted, with `""` for the root.
    private static func packages(in paths: Set<String>, members: [String]) -> [String] {
        Set(paths.compactMap(packageDirectory)).filter { directory in
            directory.isEmpty || members.contains { GlobMatcher.matches(path: directory, pattern: $0) }
        }.sorted()
    }

    /// Finds the package a library root file belongs to.
    ///
    /// - Parameter path: A repo-relative path.
    /// - Returns: The folder holding `src/lib.rs` (`""` at the root), or `nil` for any other file.
    private static func packageDirectory(_ path: String) -> String? {
        guard path == libraryRoot || path.hasSuffix("/" + libraryRoot) else { return nil }
        return String(path.dropLast(libraryRoot.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Names one package's library crate.
    ///
    /// - Parameters:
    ///   - directory: The package folder, `""` for the root.
    ///   - paths: Every indexed file's path.
    ///   - repoRoot: The repository root.
    /// - Returns: The crate name and its root file, or `nil` without a readable manifest or a package name.
    private static func library(in directory: String, paths: Set<String>, repoRoot: URL) -> (String, String)? {
        let prefix = directory.isEmpty ? "" : directory + "/"
        guard let manifest = CargoManifest.read(prefix + "Cargo.toml", repoRoot: repoRoot),
              let name = (manifest.values("name", in: "lib") + manifest.values("name", in: "package")).first
        else { return nil }
        let root = manifest.values("path", in: "lib").first.map { prefix + $0 } ?? prefix + libraryRoot
        return paths.contains(root) ? (name.replacingOccurrences(of: "-", with: "_"), root) : nil
    }
}
