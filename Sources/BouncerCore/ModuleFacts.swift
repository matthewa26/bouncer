import Foundation

/// What one file imports and exports: the per-file input to the project pass.
public struct ModuleFacts: Codable, Sendable, Equatable {
    public let imports: [ImportFact]
    public let exports: [ExportFact]
    /// Names the file refers to, for languages whose imports don't name symbols (Swift); sorted, distinct.
    public let references: [String]
    /// The file's declared types, functions, and `switch` subjects, for the cross-file design rules.
    public let structure: StructureFacts

    /// Creates module facts.
    ///
    /// - Parameters:
    ///   - imports: Every import, `require`, or re-export in the file.
    ///   - exports: Every name the file exports: TS/JS exports, or Swift `public`/`open` declarations.
    ///   - references: Names the file refers to, where usage can't be read from imports.
    ///   - structure: The file's types, functions, and `switch` subjects.
    public init(
        imports: [ImportFact], exports: [ExportFact] = [], references: [String] = [],
        structure: StructureFacts = StructureFacts()
    ) {
        self.imports = imports
        self.exports = exports
        self.references = references
        self.structure = structure
    }

    private enum CodingKeys: String, CodingKey { case imports, exports, references, structure }

    /// Decodes module facts, treating missing structure facts as empty.
    ///
    /// - Parameter decoder: The decoder.
    /// - Throws: If a field is missing or malformed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imports = try container.decode([ImportFact].self, forKey: .imports)
        exports = try container.decode([ExportFact].self, forKey: .exports)
        references = try container.decode([String].self, forKey: .references)
        structure = try container.decodeIfPresent(StructureFacts.self, forKey: .structure) ?? StructureFacts()
    }
}

/// A file's declarations as the design rules need them: types with their supertypes and members,
/// functions with their parameters, and the subjects of `switch` statements.
///
/// Parameters and fields are written `name:Type`, or just `name` when the type isn't written, which keeps
/// the cached facts compact. Empty lists are left out of the cache file.
public struct StructureFacts: Codable, Sendable, Equatable {
    public let types: [TypeFact]
    public let functions: [FunctionFact]
    public let switches: [SwitchFact]
    /// Whether the file says it's generated, so design rules leave it alone.
    public let isGenerated: Bool

    private enum CodingKeys: String, CodingKey { case types, functions, switches, isGenerated = "generated" }

    /// Creates structure facts.
    ///
    /// - Parameters:
    ///   - types: Declared types, and Swift extensions that add conformances.
    ///   - functions: Functions, methods, and initializers with bodies.
    ///   - switches: Each `switch` (or Python `match`) statement's subject.
    ///   - isGenerated: Whether the file says it's generated.
    public init(
        types: [TypeFact] = [], functions: [FunctionFact] = [], switches: [SwitchFact] = [], isGenerated: Bool = false
    ) {
        self.types = types
        self.functions = functions
        self.switches = switches
        self.isGenerated = isGenerated
    }

    /// Decodes structure facts, treating a missing list as empty.
    ///
    /// - Parameter decoder: The decoder.
    /// - Throws: If a list is malformed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        types = try container.decodeIfPresent([TypeFact].self, forKey: .types) ?? []
        functions = try container.decodeIfPresent([FunctionFact].self, forKey: .functions) ?? []
        switches = try container.decodeIfPresent([SwitchFact].self, forKey: .switches) ?? []
        isGenerated = try container.decodeIfPresent(Bool.self, forKey: .isGenerated) ?? false
    }

    /// Encodes structure facts, leaving out empty lists.
    ///
    /// - Parameter encoder: The encoder.
    /// - Throws: If encoding fails.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNonEmpty(types, forKey: .types)
        try container.encodeNonEmpty(functions, forKey: .functions)
        try container.encodeNonEmpty(switches, forKey: .switches)
        if isGenerated { try container.encode(true, forKey: .isGenerated) }
    }
}

/// What kind of type a declaration introduces.
public enum TypeKind: String, Codable, Sendable {
    case `class`, abstractClass, `struct`, `enum`, `protocol`, interface, `extension`, other

    /// Whether the kind is an abstraction: a protocol, an interface, or an abstract class.
    public var isAbstract: Bool { [.abstractClass, .protocol, .interface].contains(self) }

    /// Whether the kind is a class, abstract or not.
    public var isClass: Bool { self == .class || self == .abstractClass }
}

/// One declared type, or a Swift extension that adds conformances to one.
public struct TypeFact: Codable, Sendable, Equatable {
    public let name: String
    public let line: Int
    public let kind: TypeKind
    /// Superclasses, protocols, and interfaces as written, without generic arguments or module prefixes;
    /// for Swift, a class's superclass, if any, comes first.
    public let supertypes: [String]
    /// Stored properties (or interface properties), as `name:Type` or `name`.
    public let fields: [String]
    /// A class's method names.
    public let methods: [String]
    /// Methods whose body only throws or traps, such as `fatalError` or `raise NotImplementedError`;
    /// for Swift, only `override`s.
    public let refused: [String]
    /// Methods whose body is empty; for Swift, only `override`s.
    public let empty: [String]

    private enum CodingKeys: String, CodingKey { case name, line, kind, supertypes, fields, methods, refused, empty }

    /// Creates a type fact.
    ///
    /// - Parameters:
    ///   - name: The type's name, or the extended type's for an extension.
    ///   - line: The 1-indexed line of the declaration.
    ///   - kind: What kind of type it is.
    ///   - members: Its supertypes, fields, and methods.
    public init(name: String, line: Int, kind: TypeKind, members: TypeMembers = TypeMembers()) {
        self.name = name
        self.line = line
        self.kind = kind
        supertypes = members.supertypes
        fields = members.fields
        methods = members.methods
        refused = members.refused
        empty = members.empty
    }

    /// Decodes a type fact, treating a missing list as empty.
    ///
    /// - Parameter decoder: The decoder.
    /// - Throws: If a field is missing or malformed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        line = try container.decode(Int.self, forKey: .line)
        kind = try container.decode(TypeKind.self, forKey: .kind)
        let list = { (key: CodingKeys) in try container.decodeIfPresent([String].self, forKey: key) ?? [] }
        (supertypes, fields, methods) = (try list(.supertypes), try list(.fields), try list(.methods))
        (refused, empty) = (try list(.refused), try list(.empty))
    }

    /// Encodes a type fact, leaving out empty lists.
    ///
    /// - Parameter encoder: The encoder.
    /// - Throws: If encoding fails.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(line, forKey: .line)
        try container.encode(kind, forKey: .kind)
        let lists: [(CodingKeys, [String])] = [
            (.supertypes, supertypes), (.fields, fields), (.methods, methods), (.refused, refused), (.empty, empty)
        ]
        for (key, list) in lists { try container.encodeNonEmpty(list, forKey: key) }
    }
}

/// A type's supertypes and members, gathered while reading its declaration.
public struct TypeMembers: Sendable, Equatable {
    public var supertypes: [String]
    public var fields: [String]
    public var methods: [String]
    public var refused: [String]
    public var empty: [String]

    /// Creates a member list.
    ///
    /// - Parameters:
    ///   - supertypes: Superclasses, protocols, and interfaces.
    ///   - fields: Stored properties, as `name:Type` or `name`.
    ///   - methods: Method names.
    ///   - refused: Methods whose body only throws or traps.
    ///   - empty: Methods whose body is empty.
    public init(
        supertypes: [String] = [], fields: [String] = [], methods: [String] = [], refused: [String] = [],
        empty: [String] = []
    ) {
        self.supertypes = supertypes
        self.fields = fields
        self.methods = methods
        self.refused = refused
        self.empty = empty
    }
}

/// One function, method, or initializer with a body.
public struct FunctionFact: Codable, Sendable, Equatable {
    /// The function's name; an initializer or constructor is `<Type>.init`.
    public let name: String
    public let line: Int
    /// Its parameters, as `name:Type` or `name`, leaving out `self`, unnamed, and rest parameters.
    public let parameters: [String]

    /// Creates a function fact.
    ///
    /// - Parameters:
    ///   - name: The function's name.
    ///   - line: The 1-indexed line of the declaration.
    ///   - parameters: Its parameters.
    public init(name: String, line: Int, parameters: [String] = []) {
        self.name = name
        self.line = line
        self.parameters = parameters
    }
}

/// One `switch` (or Python `match`) statement's subject, normalized: whitespace and a leading `self.` or
/// `this.` removed, with its first case labels.
public struct SwitchFact: Codable, Sendable, Equatable {
    /// The most case labels kept per statement, which bounds the cache for generated switches.
    public static let maxCases = 12
    public let subject: String
    public let line: Int
    /// Up to `maxCases` case labels, normalized by `FactText.caseLabel(_:)`; `default` is left out.
    public let cases: [String]

    /// Creates a switch fact.
    ///
    /// - Parameters:
    ///   - subject: The normalized subject expression.
    ///   - line: The 1-indexed line of the statement.
    ///   - cases: The normalized case labels; only the first `maxCases` are kept.
    public init(subject: String, line: Int, cases: [String] = []) {
        self.subject = subject
        self.line = line
        self.cases = Array(cases.prefix(Self.maxCases))
    }
}

extension KeyedEncodingContainer {
    /// Encodes a list only if it has elements, keeping the cache file compact.
    ///
    /// - Parameters:
    ///   - list: The list.
    ///   - key: Its key.
    /// - Throws: If encoding fails.
    mutating func encodeNonEmpty<Element: Encodable>(_ list: [Element], forKey key: Key) throws {
        if !list.isEmpty { try encode(list, forKey: key) }
    }
}

/// Normalizes declaration text the same way for every language's structure facts.
public enum FactText {
    /// Reports whether a file says it's generated, in a header such as `// Code generated … DO NOT EDIT.`,
    /// `@generated`, or `Automatically generated by …`, within its first ten lines.
    ///
    /// - Parameter contents: The file's text.
    /// - Returns: Whether it's generated code, which nobody simplifies by hand.
    public static func isGenerated(_ contents: String) -> Bool {
        let header = contents.split(separator: "\n", maxSplits: 10, omittingEmptySubsequences: false).prefix(10)
            .joined(separator: "\n").lowercased()
        return ["do not edit", "@generated", "automatically generated", "auto-generated", "code generated by"]
            .contains { header.contains($0) }
    }

    /// Normalizes a `switch` subject: no whitespace, no wrapping parentheses, no leading `self.` or `this.`.
    ///
    /// - Parameter text: The subject as written.
    /// - Returns: The normalized subject, or `nil` for one that can't be a shared discriminator: `self`,
    ///   a literal, or a tuple.
    public static func subject(_ text: String) -> String? {
        var subject = text.filter { !$0.isWhitespace }
        while subject.hasPrefix("("), subject.hasSuffix(")"), isBalanced(subject.dropFirst().dropLast()) {
            subject = String(subject.dropFirst().dropLast())
        }
        for prefix in ["self.", "this."] where subject.hasPrefix(prefix) { subject.removeFirst(prefix.count) }
        let trivial = ["", "self", "this", "true", "false"].contains(subject)
            || subject.first.map { "(\"'`[".contains($0) || $0.isNumber } ?? true
            || subject.contains(",")
        return trivial ? nil : subject
    }

    /// Normalizes a case label: no whitespace, no `let`/`var` binding prefix, no associated values or call
    /// arguments, and no qualifier, so `.circle(let r)`, `Shape.circle(_)`, and `circle` are all `circle`.
    ///
    /// - Parameter text: The label as written.
    /// - Returns: The normalized label, or `nil` for an empty one or a wildcard.
    public static func caseLabel(_ text: String) -> String? {
        var label = text.filter { !$0.isWhitespace }
        for prefix in ["let", "var"] where label.hasPrefix(prefix + ".") { label.removeFirst(prefix.count) }
        let head = label.prefix { $0 != "(" }
        let isString = head.first.map { "\"'`".contains($0) } == true
        let name = isString ? String(head) : String(head.split(separator: ".").last ?? "")
        return ["", "_", "default"].contains(name) ? nil : name
    }

    /// Reduces a written type to its bare name: no generic arguments, module or namespace prefix, or
    /// optional marker, so `Foundation.NSObject` is `NSObject` and `Base<T>` is `Base`.
    ///
    /// - Parameter text: The type as written.
    /// - Returns: Its name.
    public static func typeName(_ text: String) -> String {
        let head = text.prefix { !"<([{".contains($0) }.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = head.split(separator: ".").last.map(String.init) ?? head
        return last.trimmingCharacters(in: CharacterSet(charactersIn: "?!"))
    }

    /// Writes a parameter or field the way structure facts store it.
    ///
    /// - Parameters:
    ///   - name: Its name.
    ///   - type: Its type as written, or `nil` if none is written.
    /// - Returns: `name:Type` with the type's whitespace removed, or `name`.
    public static func member(_ name: String, type: String?) -> String {
        let compact = type?.filter { !$0.isWhitespace } ?? ""
        return compact.isEmpty ? name : name + ":" + compact
    }

    /// Reports whether parentheses are balanced and never close more than they open.
    ///
    /// - Parameter text: The text.
    /// - Returns: Whether `text` could sit inside one pair of parentheses.
    private static func isBalanced(_ text: Substring) -> Bool {
        var depth = 0
        for character in text {
            if character == "(" { depth += 1 } else if character == ")" { depth -= 1 }
            if depth < 0 { return false }
        }
        return depth == 0
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
