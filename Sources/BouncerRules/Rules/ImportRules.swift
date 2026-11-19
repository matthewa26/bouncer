import BouncerCore

/// Flags a module imported twice in one file: the same Swift module, Python name, or Go path, or a TypeScript or
/// JavaScript specifier in two `import` statements of the same kind (type-only and namespace imports are kinds of
/// their own, since they can't always be merged).
///
/// Swift imports in different `#if` branches, and Python imports inside a function, `try`, or `if` block, aren't
/// compared, since importing there again is usually deliberate.
public struct DuplicateImportRule: Rule {
    public static let ruleID = "duplicate-import"
    public let id = DuplicateImportRule.ruleID

    /// Creates the rule.
    public init() {}

    /// Flags each repeated import at its second occurrence, naming the line of the first.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per repeated import.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, let statements = ImportStatements.statements(in: file) else { return [] }
        return Self.repeats(in: statements).map { statement, earlier in
            let message = "'\(statement.module)' is already imported on line \(earlier + 1); "
                + "remove or merge this import."
            return Finding(ruleID: id, severity: settings.severity, filePath: file.path, line: statement.line + 1,
                           message: message)
        }
    }

    /// Pairs each statement that repeats an earlier import with the earlier one's line.
    ///
    /// - Parameter statements: The file's import statements.
    /// - Returns: Each repeating statement and the 0-based line of the first statement it repeats.
    private static func repeats(in statements: [ImportStatement]) -> [(ImportStatement, Int)] {
        var firstLine: [String: Int] = [:]
        return statements.compactMap { statement in
            let keys = statement.duplicateKeys.map { "\(statement.region)|\($0)" }
            let earlier = keys.lazy.compactMap { firstLine[$0] }.first
            for key in keys where firstLine[key] == nil { firstLine[key] = statement.line }
            guard let earlier, earlier != statement.line else { return nil }
            return (statement, earlier)
        }
    }
}

/// Flags a group of imports that isn't in alphabetical order, in Swift, TypeScript/JavaScript, and Python.
///
/// Opt-in. A group is a run of import statements on consecutive lines; a blank line, a comment, `#if`, or a
/// side-effect import (`import "./polyfill"`) ends it, so deliberate sections stay separate. Swift sorts by module,
/// ignoring attributes such as `@testable`. TypeScript and JavaScript sort by specifier, with builtins and packages
/// before aliases (`@/`, `~`, `#`), parent (`../`), and sibling (`./`) paths. Python accepts either isort's default
/// (`import x` lines before `from x import y` lines) or one order by module, with relative imports last. Comparison
/// ignores case. Go isn't checked, since gofmt sorts imports already.
public struct UnsortedImportsRule: Rule {
    public static let ruleID = "unsorted-imports"
    public let id = UnsortedImportsRule.ruleID

    /// Creates the rule.
    public init() {}

    /// Flags the first out-of-order import in each group.
    ///
    /// Runs only when `.bouncer` enables it explicitly.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's settings.
    /// - Returns: One finding per unsorted group.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        guard let settings = context.ruleSettings[id], settings.enabled, file.language != .go,
              let statements = ImportStatements.statements(in: file) else { return [] }
        return Self.groups(of: statements).compactMap(Self.firstOutOfOrder).map { statement, successor in
            let message = "Imports aren't sorted: '\(statement.module)' should come before '\(successor.module)'."
            return Finding(ruleID: id, severity: settings.severity, filePath: file.path, line: statement.line + 1,
                           message: message)
        }
    }

    /// Splits statements into groups of sortable imports on consecutive lines in the same region.
    ///
    /// - Parameter statements: The file's import statements.
    /// - Returns: Groups of two or more statements.
    private static func groups(of statements: [ImportStatement]) -> [[ImportStatement]] {
        var groups: [[ImportStatement]] = [], previous: ImportStatement?
        for statement in statements where statement.sortKeys != nil {
            let joins = previous.map { $0.endLine + 1 == statement.line && $0.region == statement.region } ?? false
            if joins { groups[groups.count - 1].append(statement) } else { groups.append([statement]) }
            previous = statement
        }
        return groups.filter { $0.count > 1 }
    }

    /// Finds the first statement that sorts before an earlier one, unless some accepted key orders the whole group.
    ///
    /// - Parameter group: A group of sortable statements.
    /// - Returns: The out-of-order statement and the earlier one it belongs before, or `nil` if the group is sorted.
    private static func firstOutOfOrder(in group: [ImportStatement]) -> (ImportStatement, ImportStatement)? {
        let alternatives = group.first?.sortKeys?.count ?? 0
        let isSorted = (0..<alternatives).contains { key in
            zip(group, group.dropFirst()).allSatisfy { sortKey($0, key) <= sortKey($1, key) }
        }
        guard !isSorted,
              let late = group.indices.dropFirst().first(where: { sortKey(group[$0], 0) < sortKey(group[$0 - 1], 0) })
        else { return nil }
        let successor = group[..<late].first { sortKey($0, 0) > sortKey(group[late], 0) } ?? group[late - 1]
        return (group[late], successor)
    }

    /// Reads one of a statement's alternative sort keys.
    ///
    /// - Parameters:
    ///   - statement: The statement.
    ///   - alternative: Which key to read.
    /// - Returns: The key, or an empty string if it has none.
    private static func sortKey(_ statement: ImportStatement, _ alternative: Int) -> String {
        statement.sortKeys.map { $0[alternative] } ?? ""
    }
}
