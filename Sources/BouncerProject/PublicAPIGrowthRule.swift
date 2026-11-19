import Foundation
import BouncerCore

/// Reads a file's module facts, for change rules that compare a file with its base version.
public protocol ModuleFactsParsing: Sendable {
    /// Parses a file's module facts.
    ///
    /// - Parameter file: The file.
    /// - Returns: Its facts, or `nil` for a language without them or a parse failure.
    func moduleFacts(in file: SourceFile) -> ModuleFacts?
}

/// Flags public symbols a change adds, for library repos that review API growth. Off unless configured.
///
/// Each checked file's public symbols are compared with its version at the merge base of `HEAD` and `base`
/// (as `complexity-ratchet` finds it): Swift `public`/`open` declarations, TS/JS exports, and Go's
/// capitalized functions, methods, and types. The two versions' symbols are aligned by name in line order, and
/// those left over are new; a new file's symbols are reported together. Members that protocol conformances
/// require (`encode`, `hash`, `description`, `debugDescription`, `body`, `id`), test files, and paths matching
/// `ignore` are skipped.
public struct PublicAPIGrowthRule: Sendable {
    public let id = "public-api-growth"
    private let parser: ModuleFactsParsing

    /// Creates the rule.
    ///
    /// - Parameter parser: Parses each version's module facts.
    public init(parser: ModuleFactsParsing) {
        self.parser = parser
    }

    /// Compares each checked file's public symbols with its base version.
    ///
    /// - Parameters:
    ///   - files: The files being checked.
    ///   - source: Resolves the base and reads files there.
    ///   - context: Repo-wide state; the rule only runs when configured, with `base` and `ignore`.
    /// - Returns: One finding per new public symbol, or one per new file.
    public func evaluate(_ files: [SourceFile], source: ChangeSource, context: AnalysisContext) -> [Finding] {
        guard let settings = context.ruleSettings[id], settings.enabled, !files.isEmpty else { return [] }
        let configured = settings.parameters.string("base", default: "")
        let refs = configured.isEmpty ? ComplexityRatchetRule.defaultBases : [configured]
        guard let base = source.mergeBase(of: refs, in: context.repoRoot) else { return [] }
        let ignore = settings.parameters.stringList("ignore", default: [])
        return files.filter { file in
            let path = RepoPath.relative(file.path, to: context.repoRoot)
            return !ProjectUnits.isTest(path) && !ignore.contains { GlobMatcher.matches(path: path, pattern: $0) }
        }.flatMap { findings(in: $0, base: base, source: source, context: context) }
    }

    /// Compares one file with its base version.
    ///
    /// - Parameters:
    ///   - file: The file as it is now.
    ///   - base: The base ref and commit.
    ///   - source: Reads the base version.
    ///   - context: Repo-wide state.
    /// - Returns: The file's findings.
    private func findings(
        in file: SourceFile, base: (ref: String, commit: String), source: ChangeSource, context: AnalysisContext
    ) -> [Finding] {
        let path = RepoPath.relative(file.path, to: context.repoRoot), now = symbols(of: file, path: path)
        guard let first = now.first else { return [] }
        guard let old = source.contents(of: path, at: base.commit, in: context.repoRoot) else {
            return [ProjectFinding.make(id, path, first.line, Self.newFile(now, at: base), context)]
        }
        let before = symbols(of: SourceFile(path: file.path, language: file.language, contents: old), path: path)
        return Self.added(before: before, after: now).map {
            ProjectFinding.make(id, path, $0.line, Self.newSymbol($0.name, at: base), context)
        }
    }

    /// Parses one version of a file and lists its public symbols.
    ///
    /// - Parameters:
    ///   - file: The version.
    ///   - path: Its repo-relative path.
    /// - Returns: Its public symbols, or none if it can't be parsed.
    private func symbols(of file: SourceFile, path: String) -> [ExportFact] {
        parser.moduleFacts(in: file).map { Self.symbols($0, path: path) } ?? []
    }

    /// Explains a new file's public symbols.
    ///
    /// - Parameters:
    ///   - symbols: Its symbols.
    ///   - base: The base ref and commit.
    /// - Returns: The message.
    private static func newFile(_ symbols: [ExportFact], at base: (ref: String, commit: String)) -> String {
        "New file adds \(symbols.count) public symbol\(symbols.count == 1 ? "" : "s") not at \(describe(base)): "
            + "\(ManySubclassesRule.list(symbols.map(\.name)))."
    }

    /// Explains one new public symbol.
    ///
    /// - Parameters:
    ///   - name: The symbol.
    ///   - base: The base ref and commit.
    /// - Returns: The message.
    private static func newSymbol(_ name: String, at base: (ref: String, commit: String)) -> String {
        "New public symbol \"\(name)\" isn't in \(describe(base)); make sure growing the API is intended."
    }

    /// Names the base for a message.
    ///
    /// - Parameter base: The base ref and commit.
    /// - Returns: The ref and abbreviated commit, such as `main (1a2b3c4)`.
    private static func describe(_ base: (ref: String, commit: String)) -> String {
        "\(base.ref) (\(base.commit.prefix(7)))"
    }

    /// Members a protocol conformance requires (`Codable`, `Hashable`, `CustomStringConvertible`, SwiftUI's
    /// `View`), which grow a type's conformances rather than its own API.
    static let conformanceNames: Set<String> = ["body", "description", "debugDescription", "hash", "encode", "id"]

    /// Lists a file's public symbols in line order, leaving out conformance requirements.
    ///
    /// - Parameters:
    ///   - facts: The file's module facts.
    ///   - path: The file's path, for its language.
    /// - Returns: Each public symbol and its line.
    static func symbols(_ facts: ModuleFacts, path: String) -> [ExportFact] {
        guard path.hasSuffix(".go") else {
            return facts.exports.filter { !conformanceNames.contains($0.name) }.sorted { $0.line < $1.line }
        }
        let structure = facts.structure
        let declared = structure.functions.map { ExportFact(name: $0.name, line: $0.line) }
            + structure.types.map { ExportFact(name: $0.name, line: $0.line) }
        return declared.filter { $0.name.first?.isUppercase == true }.sorted { $0.line < $1.line }
    }

    /// Finds the symbols that are new: those left over when the two versions' symbol names, in line order,
    /// are aligned by their longest common subsequence, so a symbol inserted between existing ones is the one
    /// reported. Files with very many symbols fall back to counting each name.
    ///
    /// - Parameters:
    ///   - before: The base version's symbols, in line order.
    ///   - after: The current version's symbols, in line order.
    /// - Returns: The new symbols, in line order.
    static func added(before: [ExportFact], after: [ExportFact]) -> [ExportFact] {
        let old = before.map(\.name), new = after.map(\.name)
        guard old.count * new.count <= maxAligned else { return addedByCount(before: before, after: after) }
        let table = SymbolAlignment.table(old, new)
        var row = 0, result: [ExportFact] = []
        for (column, name) in new.enumerated() {
            while row < old.count, old[row] != name, table[row + 1][column] >= table[row][column + 1] { row += 1 }
            if row < old.count, old[row] == name { row += 1 } else { result.append(after[column]) }
        }
        return result
    }

    /// The most name pairs `added(before:after:)` aligns before falling back to counting.
    static let maxAligned = 4_000_000

    /// Finds new symbols by count: for each name declared more often than at the base, its last declarations.
    ///
    /// - Parameters:
    ///   - before: The base version's symbols.
    ///   - after: The current version's symbols.
    /// - Returns: The new symbols, in line order.
    private static func addedByCount(before: [ExportFact], after: [ExportFact]) -> [ExportFact] {
        let counts = Dictionary(grouping: before, by: \.name).mapValues(\.count)
        return Dictionary(grouping: after, by: \.name).flatMap { name, now in now.dropFirst(counts[name] ?? 0) }
            .sorted { ($0.line, $0.name) < ($1.line, $1.name) }
    }
}

/// Aligns two sequences of names by their longest common subsequence.
enum SymbolAlignment {
    /// Builds the suffix table: `table[i][j]` is the length of the longest common subsequence of `old[i...]`
    /// and `new[j...]`.
    ///
    /// - Parameters:
    ///   - old: The base version's names.
    ///   - new: The current version's names.
    /// - Returns: The table, `old.count + 1` rows of `new.count + 1`.
    static func table(_ old: [String], _ new: [String]) -> [[Int]] {
        var table = Array(repeating: Array(repeating: 0, count: new.count + 1), count: old.count + 1)
        for i in old.indices.reversed() {
            for j in new.indices.reversed() {
                table[i][j] = old[i] == new[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        return table
    }
}
