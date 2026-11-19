import Foundation

/// What one file imports and exports: the per-file input to the project pass.
public struct ModuleFacts: Codable, Sendable, Equatable {
    public let imports: [ImportFact]
    public let exports: [ExportFact]

    /// Creates module facts.
    ///
    /// - Parameters:
    ///   - imports: Every import, `require`, or re-export in the file.
    ///   - exports: Every name the file exports, where the language has explicit exports.
    public init(imports: [ImportFact], exports: [ExportFact] = []) {
        self.imports = imports
        self.exports = exports
    }
}

/// One import: its module specifier as written, its line, and the names it pulls in.
public struct ImportFact: Codable, Sendable, Equatable {
    public let specifier: String
    public let line: Int
    /// Imported names; `"*"` for a namespace import or `require`, `"default"` for a default import, and
    /// empty for a side-effect-only import.
    public let names: [String]

    /// Creates an import fact.
    ///
    /// - Parameters:
    ///   - specifier: The module specifier, such as `./util`, `Foundation`, or `github.com/x/y`.
    ///   - line: The 1-indexed line of the import.
    ///   - names: The names it imports.
    public init(specifier: String, line: Int, names: [String] = ["*"]) {
        self.specifier = specifier
        self.line = line
        self.names = names
    }
}

/// One exported name and the line that exports it.
public struct ExportFact: Codable, Sendable, Equatable {
    public let name: String
    public let line: Int

    /// Creates an export fact.
    ///
    /// - Parameters:
    ///   - name: The exported name, or `"default"` for a default export.
    ///   - line: The 1-indexed line of the export.
    public init(name: String, line: Int) {
        self.name = name
        self.line = line
    }
}

/// A file's module facts with the path and content hash that identify them.
public struct FileFacts: Codable, Sendable, Equatable {
    /// The repo-relative path, with `/` separators on every platform.
    public let path: String
    public let contentHash: String
    public let module: ModuleFacts

    /// Creates file facts.
    ///
    /// - Parameters:
    ///   - path: The repo-relative path.
    ///   - contentHash: A hash of the file's contents, for cache invalidation.
    ///   - module: The file's imports and exports.
    public init(path: String, contentHash: String, module: ModuleFacts) {
        self.path = path
        self.contentHash = contentHash
        self.module = module
    }
}
