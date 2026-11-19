import Foundation

/// What one file imports and exports: the per-file input to the project pass.
public struct ModuleFacts: Codable, Sendable, Equatable {
    public let imports: [ImportFact]
    public let exports: [ExportFact]
    /// Names the file refers to, for languages whose imports don't name symbols (Swift); sorted, distinct.
    public let references: [String]

    /// Creates module facts.
    ///
    /// - Parameters:
    ///   - imports: Every import, `require`, or re-export in the file.
    ///   - exports: Every name the file exports: TS/JS exports, or Swift `public`/`open` declarations.
    ///   - references: Names the file refers to, where usage can't be read from imports.
    public init(imports: [ImportFact], exports: [ExportFact] = [], references: [String] = []) {
        self.imports = imports
        self.exports = exports
        self.references = references
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
    /// The file's duplicate-code fingerprints, or `nil` when the project rules didn't compute any.
    public let clones: CloneFacts?

    /// Creates file facts.
    ///
    /// - Parameters:
    ///   - path: The repo-relative path.
    ///   - contentHash: A hash of the file's contents, for cache invalidation.
    ///   - module: The file's imports and exports.
    ///   - clones: The file's duplicate-code fingerprints, if computed.
    public init(path: String, contentHash: String, module: ModuleFacts, clones: CloneFacts? = nil) {
        self.path = path
        self.contentHash = contentHash
        self.module = module
        self.clones = clones
    }

    /// Returns a copy with different duplicate-code fingerprints.
    ///
    /// - Parameter clones: The fingerprints, or `nil` for none.
    /// - Returns: The same facts carrying `clones`.
    public func with(clones: CloneFacts?) -> FileFacts {
        FileFacts(path: path, contentHash: contentHash, module: module, clones: clones)
    }
}

/// A file's winnowed token fingerprints, for finding code duplicated across files.
///
/// Fingerprint `i` is the hash of the normalized k-gram starting at token `offsets[i]`. It spans code lines
/// `lines[i]` through `endLines[i]`, counted from 0 over lines that hold at least one token, and
/// `lineNumbers` maps each code line to its 1-indexed line in the file. The arrays are parallel, which keeps
/// the cache file compact.
public struct CloneFacts: Codable, Sendable, Equatable {
    /// Identifies the tokenizer and parameters that produced these fingerprints; others are recomputed.
    public let scheme: String
    public let hashes: [Int]
    public let offsets: [Int]
    public let lines: [Int]
    public let endLines: [Int]
    public let lineNumbers: [Int]

    /// Creates a fingerprint set.
    ///
    /// - Parameters:
    ///   - scheme: The tokenizer and parameters that produced it.
    ///   - hashes: Each fingerprint's k-gram hash.
    ///   - offsets: Each fingerprint's first token index.
    ///   - lines: Each fingerprint's first code line.
    ///   - endLines: Each fingerprint's last code line.
    ///   - lineNumbers: Each code line's 1-indexed line in the file.
    public init(scheme: String, hashes: [Int], offsets: [Int], lines: [Int], endLines: [Int], lineNumbers: [Int]) {
        self.scheme = scheme
        self.hashes = hashes
        self.offsets = offsets
        self.lines = lines
        self.endLines = endLines
        self.lineNumbers = lineNumbers
    }
}
