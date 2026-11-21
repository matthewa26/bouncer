import Foundation
import BouncerCore

/// Flags an import that the configuration forbids for the file's path, such as `UIKit` under `Sources/Domain/**`.
///
/// It does nothing until configured. `deny` lists `"<glob>=<module>,<module>"` entries (or a bare
/// `"<module>,<module>"` for every path): a file whose repo-relative path matches the glob may not import those
/// modules. `allow` lists entries of the same shape: a file matching the glob may import only those modules. A
/// module matches its own name, anything under it (`lodash` matches `lodash/fp`, `UIKit` matches `UIKit.UIView`), and
/// a trailing `*` matches any name with that prefix. Imports are read the way `duplicate-import` reads them (Swift,
/// TypeScript/JavaScript, Python, Go), plus Java `import a.b.C;` and C/C++ `#include <x>`/`"x"`.
public struct ForbiddenImportRule: Rule {
    public static let ruleID = "forbidden-import"
    public let id = ForbiddenImportRule.ruleID

    /// Creates the rule.
    public init() {}

    /// Flags each import that a `deny` entry forbids, or that an `allow` entry for the file's path leaves out.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's `deny` and `allow` parameters.
    /// - Returns: One finding per forbidden import.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        let policy = ImportPolicy(parameters: settings.parameters, path: Self.relativePath(of: file, in: context))
        guard settings.enabled, !policy.isEmpty else { return [] }
        return ForbiddenImportReader.imports(in: file).compactMap { line, module in
            policy.violation(module).map { SourceText.finding(id, settings, file, line, $0) }
        }
    }

    /// Works out a file's path relative to the repository root.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - context: Repo-wide state, for the root.
    /// - Returns: The relative path with `/` separators, or the full path if the file is outside the root.
    static func relativePath(of file: SourceFile, in context: AnalysisContext) -> String {
        let root = context.repoRoot.standardizedFileURL.path
        let path = file.path.standardizedFileURL.path
        return path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
    }
}

/// The `deny` and `allow` entries that apply to one file's path.
struct ImportPolicy {
    private let denied: [(glob: String, module: String)]
    private let allowed: [(glob: String, modules: [String])]

    /// Whether no entry applies to the path.
    var isEmpty: Bool { denied.isEmpty && allowed.isEmpty }

    /// Reads the entries from the rule's parameters, keeping those whose glob matches the path.
    ///
    /// - Parameters:
    ///   - parameters: The rule's parameters.
    ///   - path: The file's repo-relative path.
    init(parameters: RuleParameters, path: String) {
        let deny = parameters.stringList("deny", default: []).compactMap(Self.entry)
        let allow = parameters.stringList("allow", default: []).compactMap(Self.entry)
        denied = deny.filter { GlobMatcher.matches(path: path, pattern: $0.0) }
            .flatMap { glob, modules in modules.map { (glob, $0) } }
        allowed = allow.filter { GlobMatcher.matches(path: path, pattern: $0.0) }
    }

    /// Splits a `"<glob>=<module>,<module>"` entry; a bare module list applies everywhere.
    ///
    /// - Parameter entry: The configured entry.
    /// - Returns: The glob and its modules, or `nil` for an entry with no modules.
    private static func entry(_ entry: String) -> (String, [String])? {
        let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
        let glob = parts.count > 1 ? parts[0].trimmingCharacters(in: .whitespaces) : "**"
        let modules = (parts.last ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return modules.isEmpty ? nil : (glob, modules)
    }

    /// Explains why an import is forbidden here, if it is.
    ///
    /// - Parameter module: The imported module.
    /// - Returns: The finding's message, or `nil` if the import is allowed.
    func violation(_ module: String) -> String? {
        if let rule = denied.first(where: { Self.module(module, matches: $0.module) }) {
            return "'\(module)' may not be imported here (denied for '\(rule.glob)')."
        }
        let outside = allowed.first { entry in !entry.modules.contains { Self.module(module, matches: $0) } }
        return outside.map { "'\(module)' isn't among the imports allowed for '\($0.glob)'." }
    }

    /// Reports whether an imported module matches a configured name.
    ///
    /// - Parameters:
    ///   - module: The imported module, path, or specifier.
    ///   - name: The configured name, optionally ending in `*`.
    /// - Returns: Whether it's the module, a module under it, or (with `*`) shares its prefix.
    static func module(_ module: String, matches name: String) -> Bool {
        if name.hasSuffix("*") { return module.hasPrefix(String(name.dropLast())) }
        return module == name || module.hasPrefix(name + "/") || module.hasPrefix(name + ".")
    }
}

/// Reads the modules a file imports, for `ForbiddenImportRule`.
enum ForbiddenImportReader {
    private static let javaImport = TextMatching.regex(#"^\s*import\s+(?:static\s+)?([\w.]+?)(?:\.\*)?\s*;"#)
    private static let include = TextMatching.regex(#"^\s*#\s*include\s*[<"]([^>"]+)[>"]"#)
    private static let objcImport = TextMatching.regex(
        #"^\s*(?:#\s*(?:include|import)\s*[<"]|@import\s+)([^>";\s]+)"#
    )

    /// Lists a file's imports.
    ///
    /// - Parameter file: The file to read.
    /// - Returns: Each import's 0-based line and module.
    static func imports(in file: SourceFile) -> [(Int, String)] {
        if let statements = ImportStatements.statements(in: file) {
            return statements.map { ($0.line, unquoted($0.module)) }
        }
        let pattern = textPattern(for: file.language)
        return file.lines.indices.compactMap { index in
            TextMatching.captures(pattern, file.lines[index]).first.map { (index, $0[1]) }
        }
    }

    /// Picks the line pattern for a language `ImportStatements` doesn't read.
    ///
    /// - Parameter language: The file's language.
    /// - Returns: Java's `import`, C and C++'s `#include`, or Objective-C's `#import`/`#include`/`@import`
    ///   pattern, capturing the module, or `nil`.
    private static func textPattern(for language: Language) -> NSRegularExpression? {
        switch language {
        case .java: javaImport
        case .c, .cpp: include
        case .objc: objcImport
        default: nil
        }
    }

    /// Strips a Go import's alias and quotes, leaving its path.
    ///
    /// - Parameter module: The module as `ImportStatements` reports it, such as `alias "net/http"`.
    /// - Returns: The bare module, such as `net/http`.
    private static func unquoted(_ module: String) -> String {
        guard module.hasSuffix("\""), let open = module.firstIndex(of: "\"") else { return module }
        return String(module[module.index(after: open)..<module.index(before: module.endIndex)])
    }
}
