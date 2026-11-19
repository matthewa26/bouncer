import Foundation
import BouncerCore

/// Flags a Swift call that crashes the process on purpose: `fatalError` (`swift-fatal-error`, on by default), or
/// `precondition`/`preconditionFailure` (`swift-precondition`, opt-in, since a precondition is often a
/// deliberate contract check). `assert` and `assertionFailure` aren't flagged: they compile out of release builds.
///
/// Both take a `libraryOnly` parameter (default `false`). When it's set, only library code is checked, since an app
/// or command-line tool may reasonably crash where a library shouldn't, and test files are skipped. A file counts as
/// executable code when it declares `@main` or is a `main.swift`, or when a directory between it and its target
/// root has a top-level `main.swift` or a top-level Swift file declaring `@main`, or the package's `Package.swift`
/// declares an `executableTarget` named after the target. The target root is the directory right under `Sources/`;
/// outside `Sources/`, directories are climbed up to (not including) the one holding `Package.swift`, at most four
/// levels. Only files with a hit are checked this way, so the filesystem is read rarely.
public struct SwiftCrashCallRule: Rule {
    public static let fatalErrorID = "swift-fatal-error"
    public static let preconditionID = "swift-precondition"
    public let id: String
    private let call: NSRegularExpression?
    private let message: String
    private let isOptIn: Bool

    /// Creates the rule for `fatalError`.
    ///
    /// - Returns: The default-on `swift-fatal-error` rule.
    public static func makeFatalError() -> SwiftCrashCallRule {
        SwiftCrashCallRule(
            id: fatalErrorID, call: #"\bfatalError\("#, isOptIn: false,
            message: "fatalError crashes the process; throw or handle the error instead."
        )
    }

    /// Creates the rule for `precondition` and `preconditionFailure`.
    ///
    /// - Returns: The opt-in `swift-precondition` rule.
    public static func makePrecondition() -> SwiftCrashCallRule {
        SwiftCrashCallRule(
            id: preconditionID, call: #"\bprecondition"# + #"(?:Failure)?\("#, isOptIn: true,
            message: "A failed precondition crashes the process, in release builds too; throw an error instead."
        )
    }

    /// Creates a crash-call rule.
    ///
    /// - Parameters:
    ///   - id: The rule's identifier.
    ///   - call: A regex matching the call.
    ///   - isOptIn: Whether the rule runs only when `.bouncer` enables it.
    ///   - message: The finding's message.
    private init(id: String, call: String, isOptIn: Bool, message: String) {
        self.id = id
        self.call = TextMatching.regex(call)
        self.isOptIn = isOptIn
        self.message = message
    }

    /// Flags each line calling this rule's crash function.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's settings and `libraryOnly` parameter.
    /// - Returns: One finding per matching line.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = isOptIn ? SourceText.optInSettings(id, context) : context.settings(for: id)
        guard let settings, settings.enabled, file.language == .swift else { return [] }
        let hits = file.lines.indices.filter { TextMatching.matches(call, file.lines[$0]) }
        let libraryOnly = settings.parameters.bool("libraryOnly", default: false)
        guard !hits.isEmpty, !libraryOnly || !SwiftTargetKind.isExecutableOrTest(file) else { return [] }
        return hits.map { SourceText.finding(id, settings, file, $0, message) }
    }
}

/// Works out whether a Swift file belongs to an app or command-line tool rather than a library, from the files
/// around it.
enum SwiftTargetKind {
    private static let mainAttribute = TextMatching.regex(#"(?m)^\s*@main\b"#)

    private static let maxLevels = 4
    private static let sources = "Sources"

    /// Reports whether a file is test code or part of an executable target.
    ///
    /// - Parameter file: The Swift file.
    /// - Returns: Whether it's a test file, or it, a directory above it, or its package marks it as executable.
    static func isExecutableOrTest(_ file: SourceFile) -> Bool {
        if TextMatching.isTestPath(file.path) || file.path.lastPathComponent == "main.swift"
            || TextMatching.matches(mainAttribute, file.contents) {
            return true
        }
        return directories(above: file.path).contains(where: hasEntryPoint)
            || declaresExecutable(targetDirectory(of: file.path))
    }

    /// Lists the directories from a file's own up to its target root.
    ///
    /// - Parameter path: The file's location.
    /// - Returns: The directories, innermost first: up to the one under `Sources/`, or else up to the one below
    ///   `Package.swift`'s, at most `maxLevels`.
    static func directories(above path: URL) -> [URL] {
        var directories: [URL] = [], directory = path.deletingLastPathComponent()
        for _ in 0..<maxLevels {
            directories.append(directory)
            let parent = directory.deletingLastPathComponent()
            if isTargetBoundary(parent) || parent.path == directory.path { break }
            directory = parent
        }
        return directories
    }

    /// Reports whether a directory is above any target: a `Sources` directory, or a package root.
    ///
    /// - Parameter directory: The directory.
    /// - Returns: Whether climbing should stop below it.
    private static func isTargetBoundary(_ directory: URL) -> Bool {
        directory.lastPathComponent == sources
            || FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path)
    }

    /// Finds a file's target directory: the directory right under the nearest `Sources`, or its own directory.
    ///
    /// - Parameter path: The file's location.
    /// - Returns: The target directory.
    static func targetDirectory(of path: URL) -> URL {
        let components = path.deletingLastPathComponent().pathComponents
        guard let sources = components.lastIndex(of: sources), sources + 1 < components.count else {
            return path.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(components[...(sources + 1)])))
    }

    /// Reports whether a target directory holds a top-level `main.swift` or a top-level file declaring `@main`.
    ///
    /// - Parameter directory: The target directory.
    /// - Returns: Whether it has an entry point.
    private static func hasEntryPoint(_ directory: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        if names.contains("main.swift") { return true }
        return names.filter { $0.hasSuffix(".swift") }.contains { name in
            let contents = try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            return contents.map { TextMatching.matches(mainAttribute, $0) } ?? false
        }
    }

    /// Reports whether the package around a target directory declares it as an `executableTarget`.
    ///
    /// - Parameter target: The target directory, under `Sources/`.
    /// - Returns: Whether `Package.swift` next to `Sources/` names it in an `executableTarget(name:)`.
    private static func declaresExecutable(_ target: URL) -> Bool {
        let manifest = target.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Package.swift")
        guard target.deletingLastPathComponent().lastPathComponent == sources,
              let contents = try? String(contentsOf: manifest, encoding: .utf8) else { return false }
        let name = NSRegularExpression.escapedPattern(for: target.lastPathComponent)
        return TextMatching.matches(TextMatching.regex(#"executableTarget\(\s*name:\s*""# + name + "\""), contents)
    }
}
