import Foundation
import BouncerCore

/// Flags a dependency a manifest declares without a reproducible version, at the line that declares it.
///
/// - `package.json` (`dependencies`, `devDependencies`, `optionalDependencies`; peers are a range the host
///   chooses): `*`, `latest`, `x`, an empty version, a `>=`/`>` range with no upper bound, a git or GitHub
///   source without a `#<commit>`, or an `http(s)://` tarball. Ordinary ranges (`^1.2.3`, `~1.2`) are fine,
///   since the lockfile pins them; `missing-lockfile` checks it exists.
/// - `Cargo.toml` (`[dependencies]`, `[dev-dependencies]`, `[build-dependencies]`,
///   `[workspace.dependencies]`, their `[target.….dependencies]` forms, and `[dependencies.<name>]` tables):
///   version `*`, or a `git` source following a `branch` or its default branch. A `rev` pins it; a `tag` is
///   accepted, since it's how unreleased crates are conventionally pinned and `Cargo.lock` records its commit.
/// - `composer.json` (`require`, `require-dev`): `*`, a dev branch (`dev-main`, or a branch alias such as
///   `2.x-dev`) without a `#<commit>`, or a `>=`/`>` range with no upper bound. Platform requirements (`php`,
///   `ext-*`) and ordinary constraints (`^1.2`, `~1.2`, `1.2.3`, `^4.5 || ^5.0`) are fine, since `composer.lock`
///   pins them.
/// - `Package.swift`: a `.package(…)` following a `branch:` (or `.branch(…)`). Versions, ranges, and
///   `revision:` are fine, since `Package.resolved` pins them.
public struct UnpinnedDependencyRule: Rule {
    public let id = "unpinned-dependency"

    /// Creates the rule.
    public init() {}

    /// Flags each unpinned dependency in a `package.json`, `Cargo.toml`, `composer.json`, or `Package.swift`.
    ///
    /// - Parameters:
    ///   - file: The file to inspect.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per unpinned dependency.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled else { return [] }
        return Self.problems(in: file).map {
            Finding(ruleID: id, severity: settings.severity, filePath: file.path, line: $0.line, message: $0.message)
        }
    }

    /// Reads a manifest's unpinned dependencies, by its file name.
    ///
    /// - Parameter file: The file.
    /// - Returns: The problems, or none for a file that isn't a supported manifest.
    static func problems(in file: SourceFile) -> [PinProblem] {
        switch file.path.lastPathComponent {
        case "package.json": NPMPins.problems(in: file.contents)
        case "Cargo.toml": CargoPins.problems(in: file.lines)
        case "composer.json": ComposerPins.problems(in: file.contents)
        case "Package.swift": SwiftPackagePins.problems(in: file.lines)
        default: []
        }
    }
}

/// One unpinned dependency: where it's declared and what's wrong with it.
struct PinProblem: Equatable {
    let line: Int
    let message: String
}

/// Finds unpinned dependencies in a `package.json`.
///
/// Parsed with `JSONSerialization`; each dependency's line is its first quoted mention after the line naming
/// its section, so a minified manifest reports everything at line 1.
enum NPMPins {
    static let sections = ["dependencies", "devDependencies", "optionalDependencies"]

    /// Lists the manifest's unpinned dependencies.
    ///
    /// - Parameter text: The manifest's text.
    /// - Returns: The problems, or none if it isn't a JSON object.
    static func problems(in text: String) -> [PinProblem] {
        problems(in: text, sections: sections) { reason(for: $1) }
    }

    /// Lists a JSON manifest's unpinned dependencies, for `package.json` and `composer.json`.
    ///
    /// - Parameters:
    ///   - text: The manifest's text.
    ///   - sections: The top-level objects listing dependencies by name.
    ///   - judge: Explains why a dependency's version spec isn't reproducible, from its name and spec, or
    ///     returns `nil` for a pinnable one.
    /// - Returns: The problems, or none if it isn't a JSON object.
    static func problems(
        in text: String, sections: [String], judge: (String, String) -> String?
    ) -> [PinProblem] {
        guard let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { return [] }
        let lines = SourceFile.lines(of: text)
        return sections.flatMap { section in
            problems(in: json[section] as? [String: Any] ?? [:], section: section, lines: lines, judge: judge)
        }
    }

    /// Lists one section's unpinned dependencies.
    ///
    /// - Parameters:
    ///   - declared: The section's entries.
    ///   - section: The section's name, such as `devDependencies`.
    ///   - lines: The manifest's lines.
    ///   - judge: Explains why a dependency's version spec isn't reproducible.
    /// - Returns: The problems, by dependency name.
    private static func problems(
        in declared: [String: Any], section: String, lines: [Substring], judge: (String, String) -> String?
    ) -> [PinProblem] {
        let start = lines.firstIndex { $0.contains("\"\(section)\"") } ?? 0
        return declared.compactMapValues { $0 as? String }.sorted { $0.key < $1.key }.compactMap { name, spec in
            judge(name, spec).map { reason in
                let line = lines[start...].firstIndex { $0.contains("\"\(name)\"") }.map { $0 + 1 } ?? 1
                return PinProblem(line: line, message: "Dependency \"\(name)\" is \"\(spec)\", which \(reason)")
            }
        }
    }

    /// Explains why a version spec isn't reproducible.
    ///
    /// - Parameter spec: The spec as written, such as `^1.2.3` or `github:owner/repo#main`.
    /// - Returns: The explanation, or `nil` for a pinnable spec.
    static func reason(for spec: String) -> String? {
        let value = unaliased(spec.trimmingCharacters(in: .whitespaces))
        if isRemote(value) { return hasCommit(value) ? nil : "follows a branch or tag; pin it with #<commit-sha>." }
        if ["http", "https"].contains(where: { value.hasPrefix($0 + "://") }) {
            return "is a tarball URL whose contents can change; depend on a published version instead."
        }
        return rangeReason(value)
    }

    /// Explains why a version range isn't reproducible.
    ///
    /// - Parameter value: The range, such as `>=2` or `^1 || *`.
    /// - Returns: The explanation, or `nil` for a range with an upper bound.
    private static func rangeReason(_ value: String) -> String? {
        let alternatives = value.components(separatedBy: "||").map { $0.trimmingCharacters(in: .whitespaces) }
        if alternatives.contains(where: anyVersion.contains) {
            return "accepts any version; declare a range such as ^1.2.3."
        }
        let unbounded = alternatives.contains { $0.hasPrefix(">") && !$0.contains("<") }
        return unbounded ? "has no upper bound, so any future major version is accepted; add one, such as <3." : nil
    }

    private static let anyVersion: Set = ["", "*", "latest", "x", "X", "x.x", "x.x.x"]

    /// Takes the version from an alias, `npm:<package>@<version>` (`""` when it names none); any other spec is
    /// returned unchanged.
    ///
    /// - Parameter spec: The spec.
    /// - Returns: The version it asks for.
    private static func unaliased(_ spec: String) -> String {
        guard spec.hasPrefix("npm:") else { return spec }
        let target = spec.dropFirst("npm:".count)
        guard let at = target.dropFirst().lastIndex(of: "@") else { return "" }
        return String(target[target.index(after: at)...])
    }

    /// Reports whether a spec is a git source: a git URL, a hosted shorthand, or `owner/repo`.
    ///
    /// - Parameter spec: The spec.
    /// - Returns: Whether it's fetched from git.
    private static func isRemote(_ spec: String) -> Bool {
        let prefixes = ["git+", "git://", "github:", "gitlab:", "bitbucket:", "gist:"]
        if prefixes.contains(where: spec.hasPrefix) { return true }
        return TextMatching.matches(shorthand, spec)
    }

    /// Reports whether a git source names a commit after its `#`.
    ///
    /// - Parameter spec: The git spec.
    /// - Returns: Whether it's pinned to a commit.
    private static func hasCommit(_ spec: String) -> Bool {
        guard let hash = spec.lastIndex(of: "#") else { return false }
        return TextMatching.matches(commit, spec[spec.index(after: hash)...])
    }

    private static let shorthand = TextMatching.regex(#"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(#.*)?$"#)
    private static let commit = TextMatching.regex(#"^[0-9a-fA-F]{7,40}$"#)
}

/// Finds unpinned dependencies in a `Cargo.toml`, reading it line by line.
///
/// Handles dependency tables with `name = "version"` and single-line inline tables
/// (`name = { git = "…", rev = "…" }`), and `[dependencies.<name>]` tables. Dotted keys
/// (`name.git = "…"`) and multi-line inline tables aren't read.
enum CargoPins {
    /// One declared dependency and the keys that describe its source.
    struct Dependency {
        let name: String
        let line: Int
        var keys: [String: String]
    }

    private static let tables: Set = [
        "dependencies", "dev-dependencies", "build-dependencies", "dev_dependencies", "build_dependencies"
    ]
    private static let pair = TextMatching.regex(#"([A-Za-z0-9_-]+)\s*=\s*("[^"]*"|'[^']*'|[^,}\s]+)"#)

    /// Lists the manifest's unpinned dependencies.
    ///
    /// - Parameter lines: The manifest's lines.
    /// - Returns: The problems.
    static func problems(in lines: [Substring]) -> [PinProblem] {
        dependencies(in: lines).compactMap { dependency in
            reason(for: dependency.keys).map {
                PinProblem(line: dependency.line, message: "Dependency \"\(dependency.name)\" \($0)")
            }
        }
    }

    /// Collects every dependency declared in a dependency table or its own `[….dependencies.<name>]` table.
    ///
    /// - Parameter lines: The manifest's lines.
    /// - Returns: The dependencies, in order.
    static func dependencies(in lines: [Substring]) -> [Dependency] {
        var reader = Reader()
        for (index, line) in lines.enumerated() { reader.read(line, number: index + 1) }
        return reader.found
    }

    /// Reads a manifest one line at a time, tracking the table it's in.
    struct Reader {
        /// What the current table holds.
        enum Table {
            /// Not dependencies.
            case other
            /// One dependency per key, such as `[dependencies]`.
            case list
            /// One dependency's keys, such as `[dependencies.serde]`.
            case own
        }

        /// The dependencies so far.
        var found: [Dependency] = []
        /// The current table.
        var table = Table.other

        /// Reads one line: a table header, or a key in a dependency table.
        ///
        /// - Parameters:
        ///   - raw: The line as written.
        ///   - number: Its 1-indexed line number.
        mutating func read(_ raw: Substring, number: Int) {
            let line = CargoPins.uncommented(raw).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { return header(line, at: number) }
            guard table != .other, let pair = CargoPins.keyValue(line) else { return }
            if table == .own { found[found.count - 1].keys[pair.key] = CargoPins.unquoted(pair.value) } else {
                let name = CargoPins.unquoted(pair.key)
                found.append(Dependency(name: name, line: number, keys: CargoPins.keys(of: pair.value)))
            }
        }

        /// Reads a table header, starting a dependency for a `[….dependencies.<name>]` table.
        ///
        /// - Parameters:
        ///   - line: The header line, comment removed.
        ///   - number: Its 1-indexed line number.
        private mutating func header(_ line: String, at number: Int) {
            let name = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            table = CargoPins.isDependencyTable(name) ? .list : .other
            guard table == .other, let dot = CargoPins.lastDot(in: name),
                  CargoPins.isDependencyTable(String(name[..<dot])) else { return }
            let dependency = CargoPins.unquoted(String(name[name.index(after: dot)...]))
            found.append(Dependency(name: dependency, line: number, keys: [:]))
            table = .own
        }
    }

    /// Reports whether a table name lists dependencies, such as `dependencies` or
    /// `target.'cfg(unix)'.dev-dependencies`.
    ///
    /// - Parameter name: The table name.
    /// - Returns: Whether it's a dependency table.
    static func isDependencyTable(_ name: String) -> Bool {
        if tables.contains(name) || name == "workspace.dependencies" { return true }
        guard name.hasPrefix("target."), let dot = lastDot(in: name) else { return false }
        return tables.contains(String(name[name.index(after: dot)...]))
    }

    /// Explains why a dependency's source isn't reproducible.
    ///
    /// - Parameter keys: The dependency's keys; a bare version string is under `version`.
    /// - Returns: The explanation, or `nil` for a pinned one.
    static func reason(for keys: [String: String]) -> String? {
        if keys["version"] == "*" { return "accepts any version (\"*\"); declare a version such as \"1.2\"." }
        guard keys["git"] != nil, keys["rev"] == nil, keys["tag"] == nil else { return nil }
        let follows = keys["branch"].map { "branch \"\($0)\"" } ?? "its default branch"
        return "follows \(follows) of a git repository; pin it with rev = \"<commit-sha>\"."
    }

    /// Reads a dependency's value: a version string, or an inline table's keys.
    ///
    /// - Parameter value: The text after `=`.
    /// - Returns: The keys.
    static func keys(of value: String) -> [String: String] {
        guard value.hasPrefix("{") else { return ["version": unquoted(value)] }
        let pairs = TextMatching.captures(pair, value).map { ($0[1], unquoted($0[2])) }
        return Dictionary(pairs) { first, _ in first }
    }

    /// Splits a `key = value` line at its first `=`.
    ///
    /// - Parameter line: The line, comment removed and trimmed.
    /// - Returns: The trimmed key and value, or `nil` for a line without one.
    static func keyValue(_ line: String) -> (key: String, value: String)? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : (key, line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces))
    }

    /// Finds the last `.` outside quotes, which separates a table name's final part.
    ///
    /// - Parameter name: The table name.
    /// - Returns: The dot's position, or `nil` if there's none.
    static func lastDot(in name: String) -> String.Index? {
        var quote: Character?, last: String.Index?
        for index in name.indices {
            let character = name[index]
            if character == "\"" || character == "'" { quote = quote == character ? nil : (quote ?? character) }
            if character == ".", quote == nil { last = index }
        }
        return last
    }

    /// Drops a `#` comment, ignoring `#` inside quotes.
    ///
    /// - Parameter line: The raw line.
    /// - Returns: The line before any comment.
    static func uncommented(_ line: Substring) -> String {
        var quote: Character?
        for index in line.indices {
            let character = line[index]
            if character == "\"" || character == "'" { quote = quote == character ? nil : (quote ?? character) }
            if character == "#", quote == nil { return String(line[..<index]) }
        }
        return String(line)
    }

    /// Strips one pair of surrounding quotes.
    ///
    /// - Parameter text: A TOML key or string.
    /// - Returns: The text inside the quotes, or the text unchanged.
    static func unquoted(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
    }
}

/// Finds `Package.swift` dependencies that follow a branch.
///
/// Reads each `.package(` call up to its closing parenthesis, across lines; calls on comment lines are skipped.
enum SwiftPackagePins {
    private static let branch = TextMatching.regex(#"\bbranch:\s*"([^"]*)"|\.branch\(\s*"([^"]*)""#)
    private static let source = TextMatching.regex(#"\b(url|id):\s*"([^"]*)""#)
    /// How many lines after `.package(` a call may run on.
    private static let maxCallLines = 20

    /// Lists the manifest's branch dependencies.
    ///
    /// - Parameter lines: The manifest's lines.
    /// - Returns: The problems.
    static func problems(in lines: [Substring]) -> [PinProblem] {
        lines.indices.compactMap { index in
            guard let start = callStart(in: lines[index]) else { return nil }
            let call = arguments(from: lines[index][start...], following: lines[(index + 1)...])
            return problem(in: call, line: index + 1)
        }
    }

    /// Finds where a `.package(` call's arguments start, outside comment lines.
    ///
    /// - Parameter line: The line.
    /// - Returns: The position after `.package(`, or `nil` if the line has no call.
    private static func callStart(in line: Substring) -> Substring.Index? {
        guard !line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//") else { return nil }
        return line.range(of: ".package(")?.upperBound
    }

    /// Explains a call that follows a branch.
    ///
    /// - Parameters:
    ///   - call: The call's arguments.
    ///   - line: The call's 1-indexed line.
    /// - Returns: The problem, or `nil` for a call without a branch.
    private static func problem(in call: String, line: Int) -> PinProblem? {
        let branches = TextMatching.captures(branch, call).first?.dropFirst()
        guard let name = branches?.first(where: { !$0.isEmpty }) else { return nil }
        let package = TextMatching.captures(source, call).first?.last ?? "package"
        return PinProblem(line: line, message: message(package, branch: name))
    }

    /// Reads a call's arguments up to its closing parenthesis.
    ///
    /// - Parameters:
    ///   - first: The rest of the line after `.package(`.
    ///   - rest: The lines after it.
    /// - Returns: The arguments' text.
    static func arguments(from first: Substring, following rest: ArraySlice<Substring>) -> String {
        var depth = 1, text = ""
        for character in ([first] + rest.prefix(maxCallLines)).joined(separator: "\n") {
            if character == "(" { depth += 1 } else if character == ")" { depth -= 1 }
            if depth == 0 { break }
            text.append(character)
        }
        return text
    }

    /// Explains a branch dependency.
    ///
    /// - Parameters:
    ///   - package: The package's URL or registry identity.
    ///   - branch: The branch.
    /// - Returns: The message.
    private static func message(_ package: String, branch: String) -> String {
        "Package \"\(package)\" follows branch \"\(branch)\"; depend on a version (from:, exact:, or a range) "
            + "or a revision: instead."
    }
}
