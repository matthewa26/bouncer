import Foundation
import BouncerCore

/// A dependency declared in a manifest, with the line declaring it.
struct DeclaredDependency: Sendable, Equatable {
    let name: String
    let line: Int
}

/// What `unused-dependency` reads from a SwiftPM `Package.swift`: its package dependencies and each
/// target's product dependencies, parsed from the text without running the manifest.
///
/// Manifests that build their lists in variables or functions parse only partly, so a package counts as
/// used whenever its identity appears quoted anywhere else in the manifest, and a target is checked only
/// for the `.product(name:package:)` entries written inside its own declaration.
struct SwiftPackageManifest {
    /// One target: its name, kind, source folder (repo-relative), and product dependencies.
    struct Target {
        let name: String
        let kind: String
        let directory: String
        let products: [DeclaredDependency]
    }

    private static let targetKinds = ["target", "executableTarget", "testTarget", "macro", "plugin"]
    let path: String
    /// Each `.package(…)` by identity: its `name:`, else the last component of its `url:` or resolved `path:`.
    let packages: [DeclaredDependency]
    let targets: [Target]
    /// The manifest's text with comments blanked out, lines preserved.
    private let code: String
    private let packageRanges: [Range<String.Index>]

    /// Parses a manifest.
    ///
    /// - Parameters:
    ///   - path: The manifest's repo-relative path.
    ///   - repoRoot: The repository root, to name `path:` dependencies by their folder.
    ///   - text: Its contents.
    init(path: String, repoRoot: URL, text: String) {
        self.path = path
        let code = ManifestText.stripComments(text), directory = ProjectPath.directory(of: path)
        let packageCalls = ManifestText.calls(named: ["package"], in: code)
        (self.code, packageRanges) = (code, packageCalls.map(\.range))
        packages = Self.packages(packageCalls, in: code, folder: RepoPath.url(directory, in: repoRoot))
        let calls = ManifestText.calls(named: Self.targetKinds, in: code)
        targets = calls.compactMap { Self.target($0, in: code, directory: directory) }
    }

    /// Reads each `.package(…)` call's identity.
    ///
    /// - Parameters:
    ///   - calls: The calls.
    ///   - code: The manifest's code.
    ///   - folder: The manifest's folder, which `path:` dependencies are relative to.
    /// - Returns: Each package's identity and line.
    private static func packages(_ calls: [ManifestText.Call], in code: String, folder: URL) -> [DeclaredDependency] {
        calls.compactMap { call in
            identity(of: String(code[call.range]), folder: folder).map { DeclaredDependency(name: $0, line: call.line) }
        }
    }

    /// Reports whether a package's identity is mentioned, quoted, anywhere outside `.package(…)` calls.
    ///
    /// - Parameter identity: The package identity.
    /// - Returns: Whether a target (or anything else) refers to it.
    func mentions(_ identity: String) -> Bool {
        let quoted = "\"" + identity + "\""
        var start = code.startIndex
        while let found = code.range(of: quoted, options: .caseInsensitive, range: start..<code.endIndex) {
            if !packageRanges.contains(where: { $0.contains(found.lowerBound) }) { return true }
            start = found.upperBound
        }
        return false
    }

    /// Reads a package dependency's identity.
    ///
    /// - Parameters:
    ///   - call: The `.package(…)` call's text.
    ///   - folder: The manifest's folder, which a `path:` is relative to.
    /// - Returns: Its `name:`, its URL's last component without `.git`, or its path's folder name.
    private static func identity(of call: String, folder: URL) -> String? {
        if let name = ManifestText.argument("name", in: call) { return name }
        if let path = ManifestText.argument("path", in: call) {
            return folder.appendingPathComponent(path).standardizedFileURL.lastPathComponent
        }
        guard let location = ManifestText.argument("url", in: call) else { return nil }
        let last = location.split(separator: "/").last.map(String.init) ?? location
        return last.hasSuffix(".git") ? String(last.dropLast(".git".count)) : last
    }

    /// Reads one target declaration.
    ///
    /// - Parameters:
    ///   - call: The target call.
    ///   - code: The manifest's code.
    ///   - directory: The manifest's folder.
    /// - Returns: The target, or `nil` without a name.
    private static func target(_ call: ManifestText.Call, in code: String, directory: String) -> Target? {
        let text = String(code[call.range])
        guard let name = ManifestText.argument("name", in: text) else { return nil }
        let folder = ["testTarget": "Tests", "plugin": "Plugins"][call.name] ?? "Sources"
        let relative = ManifestText.argument("path", in: text) ?? folder + "/" + name
        let resolved = ProjectPath.join(directory, relative) ?? relative
        return Target(name: name, kind: call.name, directory: resolved, products: products(in: call, code: code))
    }

    /// Lists the `.product(name:…)` dependencies written inside one target declaration.
    ///
    /// - Parameters:
    ///   - call: The target call.
    ///   - code: The manifest's code.
    /// - Returns: Each product's name and line.
    private static func products(in call: ManifestText.Call, code: String) -> [DeclaredDependency] {
        ManifestText.calls(named: ["product"], in: code, within: call.range).compactMap { product in
            ManifestText.argument("name", in: String(code[product.range])).map {
                DeclaredDependency(name: $0, line: product.line)
            }
        }
    }
}

/// Text scanning for Swift manifests: comment stripping and finding `.name(…)` calls with their arguments.
enum ManifestText {
    /// One `.name(…)` call: which name, its 1-indexed line, and the range from its `.` to its closing `)`.
    struct Call {
        let name: String
        let line: Int
        let range: Range<String.Index>
    }

    /// Blanks out `//` and `/* */` comments, keeping newlines so line numbers still match.
    ///
    /// - Parameter text: The source.
    /// - Returns: The source without comments.
    static func stripComments(_ text: String) -> String {
        let pattern = #"("(?:\\.|[^"\\\n])*")|//[^\n]*|/\*[\s\S]*?\*/"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let comments = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .filter { $0.range(at: 1).location == NSNotFound }
        let stripped = comments.reversed().reduce(text as NSString) { result, match in
            result.replacingCharacters(in: match.range, with: blanked(result.substring(with: match.range))) as NSString
        }
        return stripped as String
    }

    /// Replaces every character but newlines with a space, so stripped comments keep line numbers.
    ///
    /// - Parameter text: The comment text.
    /// - Returns: Blank text of the same shape.
    private static func blanked(_ text: String) -> String {
        let characters: [Character] = text.map { $0 == "\n" ? "\n" : " " }
        return String(characters)
    }

    /// Finds `.name(…)` calls, skipping matches inside an earlier match's arguments so nested calls of the
    /// same names aren't reported separately.
    ///
    /// - Parameters:
    ///   - names: The call names, without the leading `.`.
    ///   - code: The comment-free source.
    ///   - bounds: The range to search, or the whole source.
    /// - Returns: The calls, in order.
    static func calls(named names: [String], in code: String, within bounds: Range<String.Index>? = nil) -> [Call] {
        let pattern = #"\.("# + names.joined(separator: "|") + #")\s*\("#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: code, range: NSRange(bounds ?? code.startIndex..<code.endIndex, in: code))
        return matches.compactMap { call($0, in: code) }.reduce(into: []) { calls, call in
            if call.range.lowerBound >= (calls.last?.range.upperBound ?? code.startIndex) { calls.append(call) }
        }
    }

    /// Builds a call from a regular-expression match of its name and opening parenthesis.
    ///
    /// - Parameters:
    ///   - match: The match.
    ///   - code: The source.
    /// - Returns: The call, or `nil` if the match's ranges don't map onto the source.
    private static func call(_ match: NSTextCheckingResult, in code: String) -> Call? {
        guard let whole = Range(match.range, in: code), let name = Range(match.range(at: 1), in: code) else {
            return nil
        }
        let end = closingParenthesis(in: code, from: code.index(before: whole.upperBound))
        return Call(name: String(code[name]), line: line(of: whole.lowerBound, in: code), range: whole.lowerBound..<end)
    }

    /// Reads a string argument, such as `name: "Foo"`.
    ///
    /// - Parameters:
    ///   - label: The argument label.
    ///   - call: The call's text.
    /// - Returns: The string's contents, from the first such argument.
    static func argument(_ label: String, in call: String) -> String? {
        let pattern = "\\b" + label + #"\s*:\s*"([^"]*)""#
        guard let range = call.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(call[range])
        return match.split(separator: "\"", omittingEmptySubsequences: false).dropFirst().first.map(String.init)
    }

    /// Finds the end of a parenthesized group, skipping string literals.
    ///
    /// - Parameters:
    ///   - code: The source.
    ///   - open: The index of the opening `(`.
    /// - Returns: The index just past the matching `)`, or the end of the source.
    private static func closingParenthesis(in code: String, from open: String.Index) -> String.Index {
        var depth = 0, inString = false, index = open
        while index < code.endIndex {
            let character = code[index]
            if character == "\"" { inString.toggle() }
            if !inString { depth += ["(": 1, ")": -1][character] ?? 0 }
            index = code.index(after: index)
            if depth == 0 { return index }
        }
        return code.endIndex
    }

    /// Converts an index to a 1-indexed line.
    ///
    /// - Parameters:
    ///   - index: The index.
    ///   - code: The source.
    /// - Returns: The line.
    static func line(of index: String.Index, in code: String) -> Int {
        code[..<index].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }
}

/// What `unused-dependency` reads from a Go `go.mod`: its module path and direct requirements.
struct GoModule {
    let path: String
    let module: String
    /// Each required module not marked `// indirect`.
    let requirements: [DeclaredDependency]

    /// Parses a `go.mod`.
    ///
    /// - Parameters:
    ///   - path: Its repo-relative path.
    ///   - text: Its contents.
    init(path: String, text: String) {
        self.path = path
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        module = lines.first { $0.hasPrefix("module ") }.map { String($0.dropFirst("module ".count)) } ?? ""
        var inBlock = false
        requirements = lines.enumerated().compactMap { offset, line in
            if line.hasPrefix("require (") { inBlock = true } else if inBlock, line.hasPrefix(")") { inBlock = false }
            return Self.requirement(line, inBlock: inBlock).map { DeclaredDependency(name: $0, line: offset + 1) }
        }
    }

    /// Reads one requirement line, `path version` in a `require (…)` block or after `require`, unless it's
    /// marked `// indirect`.
    ///
    /// - Parameters:
    ///   - line: The trimmed line.
    ///   - inBlock: Whether it's inside a `require (…)` block.
    /// - Returns: The module path, or `nil`.
    private static func requirement(_ line: String, inBlock: Bool) -> String? {
        let single = line.hasPrefix("require ") ? String(line.dropFirst("require ".count)) : ""
        let entry = inBlock ? line : single
        let fields = entry.split(separator: " ")
        guard fields.count >= 2, !entry.contains("// indirect"), !fields[0].hasPrefix("//"),
              fields[0] != "require", fields[0] != "(" else { return nil }
        return String(fields[0])
    }
}
