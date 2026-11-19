import Foundation
import BouncerCore

/// Flags a TypeScript or JavaScript named export that nothing else in the project imports.
///
/// Default exports are skipped, since frameworks load them by convention (pages, stories, configs), and so
/// are entry points: `index` files, declaration files, tests, and anything matching `entryPoints`.
public struct UnusedExportRule: ProjectRule {
    public let id = "unused-export"
    private static let extensions = Set(JavaScriptImportResolver.extensions)
    private static let defaultEntryPoints = [
        "**/index.*", "**/*.d.ts", "**/*.test.*", "**/*.spec.*", "**/*.stories.*", "**/*.config.*"
    ]

    /// Creates the rule.
    public init() {}

    /// Flags each named export with no importer.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph.
    ///   - targets: Unused; each finding lands at the export.
    ///   - context: Repo-wide state, including the `entryPoints` parameter.
    /// - Returns: One finding per unused export.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let configured = context.settings(for: id).parameters.stringList("entryPoints", default: [])
        let entryPoints = Self.defaultEntryPoints + configured
        let used = Dictionary(grouping: index.edges, by: \.to).mapValues { Set($0.flatMap(\.names)) }
        let files = index.facts.values.filter { isCandidate($0.path, entryPoints) }.sorted { $0.path < $1.path }
        return files.flatMap { unusedExports(in: $0, imported: used[$0.path] ?? [], context: context) }
    }

    /// Flags a file's named exports that none of its importers pull in.
    ///
    /// - Parameters:
    ///   - fact: The file's facts.
    ///   - imported: Every name imported from the file, with `*` for a namespace import.
    ///   - context: Repo-wide state, for the repo root and the rule's severity.
    /// - Returns: One finding per unused export.
    private func unusedExports(in fact: FileFacts, imported: Set<String>, context: AnalysisContext) -> [Finding] {
        let unused = fact.module.exports.filter {
            $0.name != "default" && !imported.contains($0.name) && !imported.contains("*")
        }
        return unused.map { item in
            let message = "Export \"\(item.name)\" isn't imported anywhere in the project."
            return ProjectFinding.make(id, fact.path, item.line, message, context)
        }
    }

    /// Reports whether a file's exports are checked: a TS/JS file that isn't an entry point.
    ///
    /// - Parameters:
    ///   - path: The repo-relative path.
    ///   - entryPoints: Globs for files whose exports are used from outside the project.
    /// - Returns: Whether to check it.
    private func isCandidate(_ path: String, _ entryPoints: [String]) -> Bool {
        Self.extensions.contains((path as NSString).pathExtension.lowercased())
            && !entryPoints.contains { GlobMatcher.matches(path: path, pattern: $0) }
    }
}

/// Flags a source file with no test file named after it. Off unless configured, since conventions vary.
///
/// Matches `foo.test.ts`/`foo.spec.ts` (TS/JS), `test_foo.py`/`foo_test.py` (Python), `foo_test.go`
/// (Go), and `FooTests.swift`/`FooTest.swift` (Swift), anywhere in the project.
public struct MissingTestFileRule: ProjectRule {
    public let id = "missing-test-file"

    /// Creates the rule.
    public init() {}

    /// Flags each source file whose conventional test file doesn't exist.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph.
    ///   - targets: Unused; each finding lands in the untested file.
    ///   - context: Repo-wide state; the rule only runs when configured explicitly.
    /// - Returns: One finding per untested file.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        guard context.ruleSettings[id]?.enabled == true else { return [] }
        let names = Set(index.facts.keys.map { ($0 as NSString).lastPathComponent })
        return index.facts.keys.sorted().compactMap { path in
            let candidates = TestNames.candidates(for: path)
            guard !candidates.isEmpty, !candidates.contains(where: names.contains) else { return nil }
            let expected = candidates.joined(separator: ", ")
            return ProjectFinding.make(id, path, 1, "No test file found; expected one of: \(expected).", context)
        }
    }
}

/// Test file naming conventions per language.
enum TestNames {
    /// Lists the test file names that would cover a source file.
    ///
    /// - Parameter path: The source file's repo-relative path.
    /// - Returns: The candidate test file names, or none if the file is itself a test or an entry point.
    static func candidates(for path: String) -> [String] {
        let name = (path as NSString).lastPathComponent, ext = (path as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        guard !isTestOrEntry(path, stem: stem) else { return [] }
        return names(stem: stem, ext: ext)
    }

    /// Lists the conventional test file names for a source file's language.
    ///
    /// - Parameters:
    ///   - stem: The source file name without its extension.
    ///   - ext: The source file's extension.
    /// - Returns: The candidate test file names, or none for a language without a convention.
    private static func names(stem: String, ext: String) -> [String] {
        switch ext {
        case "ts", "tsx", "js", "jsx", "mts", "cts", "mjs", "cjs": return ["\(stem).test.\(ext)", "\(stem).spec.\(ext)"]
        case "py": return ["test_\(stem).py", "\(stem)_test.py"]
        case "go": return ["\(stem)_test.go"]
        case "swift": return ["\(stem)Tests.swift", "\(stem)Test.swift"]
        default: return []
        }
    }

    /// Reports whether a file is itself a test, or a file tests don't usually target.
    ///
    /// - Parameters:
    ///   - path: The repo-relative path.
    ///   - stem: The file name without its extension.
    /// - Returns: Whether to skip it.
    private static func isTestOrEntry(_ path: String, stem: String) -> Bool {
        let testish = [".test", ".spec", "Tests", "Test"].contains { stem.hasSuffix($0) }
            || stem.hasPrefix("test_") || stem.hasSuffix("_test")
        let skipped = ["index", "__init__", "main", "Package"].contains(stem) || path.hasSuffix(".d.ts")
        let inTestFolder = path.split(separator: "/").contains { ["Tests", "tests", "__tests__", "test"].contains($0) }
        return testish || skipped || inTestFolder
    }
}
