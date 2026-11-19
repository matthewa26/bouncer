import Foundation
import BouncerCore

/// One import statement, read from a file's text, with what the import rules compare.
struct ImportStatement: Sendable {
    /// The 0-based index of the statement's first line.
    let line: Int
    /// The 0-based index of its last line (the same as `line` unless it spans several).
    let endLine: Int
    /// The conditional-compilation region it's in (Swift `#if` branches), so imports in different branches never
    /// count as duplicates or as one group.
    let region: String
    /// What it imports, for messages: a module, path, or specifier.
    let module: String
    /// One key per thing it imports; two statements sharing a key import the same thing twice.
    let duplicateKeys: [String]
    /// Alternative sort keys, any of which may order a sorted group, or `nil` if the statement must stay where it
    /// is (a side-effect import), which ends its group.
    let sortKeys: [String]?
}

/// Reads a file's top-level import statements, per language, for the import rules.
enum ImportStatements {
    /// The most lines one import statement may span before the reader gives up on it.
    private static let maxStatementLines = 50

    /// Reads every import statement in a file.
    ///
    /// - Parameter file: The file to read.
    /// - Returns: The statements in file order, or `nil` for a language the import rules don't cover.
    static func statements(in file: SourceFile) -> [ImportStatement]? {
        switch file.language {
        case .swift: SwiftImports.statements(in: file)
        case .typescript, .javascript: collect(in: file, parse: ScriptImports.statement(at:in:))
        case .python: collect(in: file, parse: PythonImports.statement(at:in:))
        case .go: GoImports.statements(in: file)
        default: nil
        }
    }

    /// Walks a file's lines outside multi-line strings, letting a parser consume one statement at a time.
    ///
    /// - Parameters:
    ///   - file: The file to read.
    ///   - parse: Reads the statement starting at a line, if one does, returning it with its last line.
    /// - Returns: The statements in file order.
    static func collect(in file: SourceFile, parse: (Int, SourceFile) -> ImportStatement?) -> [ImportStatement] {
        let interior = MultilineStringMask.interiorLines(of: file)
        var statements: [ImportStatement] = [], index = 0
        while index < file.lines.count {
            let statement = interior[index] ? nil : parse(index, file)
            if let statement { statements.append(statement) }
            index = (statement?.endLine ?? index) + 1
        }
        return statements
    }

    /// Joins the lines of a statement that may span several, up to the first line that completes it.
    ///
    /// - Parameters:
    ///   - start: The statement's first line.
    ///   - file: The file it's in.
    ///   - comment: The line-comment marker to cut each line at, if the statement may contain comments.
    ///   - isComplete: Reports whether the text so far is a whole statement.
    /// - Returns: The joined text and its last line, or `nil` if it doesn't complete within `maxStatementLines`.
    static func join(from start: Int, in file: SourceFile, cutting comment: Character? = nil,
                     until isComplete: (String) -> Bool) -> (String, Int)? {
        var text = ""
        for index in start..<min(file.lines.count, start + maxStatementLines) {
            let line = file.lines[index].prefix { $0 != comment }.trimmingCharacters(in: .whitespaces)
            text += (text.isEmpty ? "" : " ") + line
            if isComplete(text) { return (text, index) }
        }
        return nil
    }
}

/// Swift imports: `import Foo`, `@testable import Foo`, `public import Foo`, and `import struct Foo.Bar`.
enum SwiftImports {
    private static let pattern = TextMatching.regex(
        #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|package|internal|fileprivate|private)\s+)?import\s+"#
            + #"(?:(typealias|struct|class|enum|protocol|let|var|func)\s+)?([\w.]+)\s*(?://.*)?$"#
    )

    /// Reads every Swift import, tracking which `#if` branch each one is in.
    ///
    /// - Parameter file: The file to read.
    /// - Returns: The statements in file order.
    static func statements(in file: SourceFile) -> [ImportStatement] {
        let interior = MultilineStringMask.interiorLines(of: file)
        var regions = ConditionalRegions()
        return file.lines.enumerated().compactMap { index, line in
            guard !interior[index] else { return nil }
            regions.track(line)
            let match = TextMatching.captures(pattern, line).first
            return match.map { statement(from: $0, at: index, region: regions.key) }
        }
    }

    /// Builds a Swift import statement from its parsed parts.
    ///
    /// - Parameters:
    ///   - match: The whole match, the import kind (`struct`, `func`, or empty), and the module path.
    ///   - index: The statement's line.
    ///   - region: Its `#if` branch.
    /// - Returns: The statement, keyed by kind and path and sorted by path, ignoring attributes.
    private static func statement(from match: [String], at index: Int, region: String) -> ImportStatement {
        let key = match[1].isEmpty ? match[2] : "\(match[1]) \(match[2])"
        return ImportStatement(line: index, endLine: index, region: region, module: match[2],
                               duplicateKeys: [key], sortKeys: [match[2].lowercased(), match[2]])
    }
}

/// Tracks the `#if`/`#elseif`/`#else`/`#endif` branch a line is in.
struct ConditionalRegions {
    private var stack: [Int] = []
    private var nextBranch = 0

    /// A key naming the current branch, empty outside any `#if`.
    var key: String { stack.map(String.init).joined(separator: ".") }

    /// Updates the current branch for a line that opens, switches, or closes a conditional block.
    ///
    /// - Parameter line: The line to read.
    mutating func track(_ line: Substring) {
        let trimmed = line.drop(while: \.isWhitespace)
        nextBranch += 1
        if trimmed.hasPrefix("#else"), !stack.isEmpty { stack[stack.count - 1] = nextBranch }
        if trimmed.hasPrefix("#endif") { _ = stack.popLast() }
        if trimmed.hasPrefix("#if") { stack.append(nextBranch) }
    }
}

/// TypeScript and JavaScript `import` statements, including multi-line and side-effect imports.
enum ScriptImports {
    private static let start = TextMatching.regex(#"^import(?:\s|\{|\*|'|")(?!\s*\()(?![^=]*=)"#)
    private static let complete = TextMatching.regex(#"\bfrom\s*['"][^'"]+['"]|^import\s*['"][^'"]+['"]"#)
    private static let sideEffect = TextMatching.regex(#"^import\s*['"]([^'"]+)['"]"#)
    private static let fromClause = TextMatching.regex(#"^import\s+(type\s+)?(.*?)\s*\bfrom\s*['"]([^'"]+)['"]"#)
    /// The `fromClause` capture group holding the module specifier.
    private static let specifierGroup = 3
    private static let builtins: Set = [
        "assert", "async_hooks", "buffer", "child_process", "cluster", "crypto", "dns", "events", "fs",
        "fs/promises", "http", "http2", "https", "module", "net", "os", "path", "perf_hooks", "process",
        "querystring", "readline", "stream", "string_decoder", "timers", "tls", "url", "util", "v8", "vm",
        "worker_threads", "zlib"
    ]

    /// Reads the import statement starting at a line, if one does.
    ///
    /// - Parameters:
    ///   - index: The candidate first line.
    ///   - file: The file it's in.
    /// - Returns: The statement, or `nil` if the line doesn't start a static import.
    static func statement(at index: Int, in file: SourceFile) -> ImportStatement? {
        guard TextMatching.matches(start, file.lines[index]),
              let (text, end) = ImportStatements.join(from: index, in: file, until: isComplete) else { return nil }
        if let specifier = TextMatching.captures(sideEffect, text).first?[1] {
            return ImportStatement(line: index, endLine: end, region: "", module: specifier,
                                   duplicateKeys: ["side-effect \(specifier)"], sortKeys: nil)
        }
        return TextMatching.captures(fromClause, text).first.map { fromStatement($0, from: index, to: end) }
    }

    /// Builds the statement for an `import … from "x"`.
    ///
    /// - Parameters:
    ///   - match: The `from` clause match: type marker, bindings, and specifier.
    ///   - line: The statement's first line.
    ///   - end: Its last line.
    /// - Returns: The statement, keyed by kind and specifier.
    private static func fromStatement(_ match: [String], from line: Int, to end: Int) -> ImportStatement {
        let specifier = match[specifierGroup]
        return ImportStatement(line: line, endLine: end, region: "", module: specifier,
                               duplicateKeys: ["\(kind(of: match)) \(specifier)"], sortKeys: sortKeys(for: specifier))
    }

    /// Reports whether the joined text so far is a whole import statement, ending in its module specifier.
    ///
    /// - Parameter text: The statement's text so far.
    /// - Returns: Whether the specifier has been reached.
    private static func isComplete(_ text: String) -> Bool {
        TextMatching.matches(complete, text)
    }

    /// Names the kind of import a statement is, since type-only and namespace imports can't merge with others.
    ///
    /// - Parameter match: The `from` clause match: type marker, bindings, and specifier.
    /// - Returns: `"type"`, `"namespace"`, or `"value"`.
    private static func kind(of match: [String]) -> String {
        if !match[1].isEmpty { return "type" }
        return match[2].contains("* as") ? "namespace" : "value"
    }

    /// Builds the accepted sort keys for a specifier: by group (builtin, package, alias, parent, sibling), with or
    /// without builtins separated from packages.
    ///
    /// - Parameter specifier: The module specifier.
    /// - Returns: The alternative keys.
    private static func sortKeys(for specifier: String) -> [String] {
        let name = specifier.lowercased(), rank = group(of: name)
        let isBuiltin = name.hasPrefix("node:") || builtins.contains(name)
        return ["\(isBuiltin ? "0" : rank) \(name)", "\(rank) \(name)", "\(rank) \(specifier)"]
    }

    /// Ranks a specifier's group: packages (builtins included), then aliases, parent paths, and sibling paths.
    ///
    /// - Parameter name: The lowercased specifier.
    /// - Returns: The group's rank, as a sortable digit.
    private static func group(of name: String) -> String {
        if name.hasPrefix("../") { return "3" }
        if name.hasPrefix(".") { return "4" }
        return name.hasPrefix("@/") || name.hasPrefix("~") || name.hasPrefix("#") ? "2" : "1"
    }
}

/// Python `import a, b as c` and `from x import (y, z)` statements at module level.
enum PythonImports {
    private static let start = TextMatching.regex(#"^(import|from)\s+[\w.]"#)
    private static let fromClause = TextMatching.regex(#"^from\s+([\w.]+)\s+import\s+(.+)$"#)

    /// Reads the module-level import statement starting at a line, if one does.
    ///
    /// - Parameters:
    ///   - index: The candidate first line.
    ///   - file: The file it's in.
    /// - Returns: The statement, or `nil` if the line doesn't start an unindented import.
    static func statement(at index: Int, in file: SourceFile) -> ImportStatement? {
        guard TextMatching.matches(start, file.lines[index]),
              let (raw, end) = ImportStatements.join(from: index, in: file, cutting: "#", until: isComplete)
        else { return nil }
        let text = raw.replacingOccurrences(of: "\\", with: " ")
        if let match = TextMatching.captures(fromClause, text).first {
            let names = entries(match[2]).map { "from \(match[1]) import \($0)" }
            return statement(index, end, module: match[1], keys: names, style: "1")
        }
        return plainImport(text, from: index, to: end)
    }

    /// Reads an `import a, b as c` statement.
    ///
    /// - Parameters:
    ///   - text: The statement's joined text.
    ///   - line: Its first line.
    ///   - end: Its last line.
    /// - Returns: The statement, named after its first module.
    private static func plainImport(_ text: String, from line: Int, to end: Int) -> ImportStatement {
        let modules = entries(String(text.dropFirst("import".count)))
        return statement(line, end, module: modules.first ?? "", keys: modules.map { "import \($0)" }, style: "0")
    }

    /// Reports whether the joined text so far is a whole statement: no open parenthesis or trailing backslash.
    ///
    /// - Parameter text: The statement's text so far, comments removed.
    /// - Returns: Whether the statement is complete.
    private static func isComplete(_ text: String) -> Bool {
        !text.hasSuffix("\\") && text.filter({ $0 == "(" }).count <= text.filter({ $0 == ")" }).count
    }

    /// Splits an import list into its normalized entries, dropping parentheses.
    ///
    /// - Parameter list: The text after `import`.
    /// - Returns: Entries such as `"os"` or `"path as p"`.
    private static func entries(_ list: String) -> [String] {
        list.components(separatedBy: CharacterSet(charactersIn: ",()"))
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
    }

    /// Builds a Python import statement with its sort keys: by style then module (isort's default), or by module.
    ///
    /// - Parameters:
    ///   - line: The first line.
    ///   - end: The last line.
    ///   - module: The imported module.
    ///   - keys: Its duplicate keys.
    ///   - style: `"0"` for `import x`, `"1"` for `from x import y`.
    /// - Returns: The statement.
    private static func statement(_ line: Int, _ end: Int, module: String, keys: [String], style: String)
        -> ImportStatement {
        let name = (module.hasPrefix(".") ? "1 " : "0 ") + module.lowercased()
        return ImportStatement(line: line, endLine: end, region: "", module: module, duplicateKeys: keys,
                               sortKeys: ["\(style) \(name)", name])
    }
}

/// Go imports, single or in an `import ( … )` block; Go isn't sorted here, since gofmt already sorts.
enum GoImports {
    private static let single = TextMatching.regex(#"^import\s+((?:[\w.]+\s+)?"[^"]+")"#)
    private static let blockEntry = TextMatching.regex(#"^\s*((?:[\w.]+\s+)?"[^"]+")\s*(?://.*)?$"#)

    /// Reads every Go import, one statement per imported path.
    ///
    /// - Parameter file: The file to read.
    /// - Returns: The imports in file order.
    static func statements(in file: SourceFile) -> [ImportStatement] {
        var inBlock = false
        return file.lines.enumerated().compactMap { index, line in
            if line.hasPrefix("import (") || (inBlock && line.hasPrefix(")")) { inBlock.toggle(); return nil }
            let match = TextMatching.captures(inBlock ? blockEntry : single, line).first
            guard let spec = match?[1].split(whereSeparator: \.isWhitespace).joined(separator: " ") else { return nil }
            return ImportStatement(line: index, endLine: index, region: "", module: spec, duplicateKeys: [spec],
                                   sortKeys: nil)
        }
    }
}
