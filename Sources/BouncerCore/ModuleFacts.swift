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
    /// What each type's code reads from and constructs of other types.
    public let collaborations: [CollaborationFact]
    /// Whether the file says it's generated, so design rules leave it alone.
    public let isGenerated: Bool

    private enum CodingKeys: String, CodingKey {
        case types, functions, switches, collaborations, isGenerated = "generated"
    }

    /// Creates structure facts.
    ///
    /// - Parameters:
    ///   - types: Declared types, and Swift extensions that add conformances.
    ///   - functions: Functions, methods, and initializers with bodies.
    ///   - switches: Each `switch` (or Python `match`) statement's subject.
    ///   - collaborations: What each type reads from and constructs of other types.
    ///   - isGenerated: Whether the file says it's generated.
    public init(
        types: [TypeFact] = [], functions: [FunctionFact] = [], switches: [SwitchFact] = [],
        collaborations: [CollaborationFact] = [], isGenerated: Bool = false
    ) {
        self.types = types
        self.functions = functions
        self.switches = switches
        self.collaborations = collaborations
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
        collaborations = try container.decodeIfPresent([CollaborationFact].self, forKey: .collaborations) ?? []
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
        try container.encodeNonEmpty(collaborations, forKey: .collaborations)
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
    /// Swift only: methods marked `override`.
    public let overrides: [String]
    /// Swift only: methods that aren't `override`s whose body only throws or traps.
    public let refusedOwn: [String]
    /// Swift only: methods that aren't `override`s whose body is empty.
    public let emptyOwn: [String]
    /// Methods whose body opens with a precondition that traps or throws, such as `precondition(…)`,
    /// `guard … else { fatalError() }`, `if (…) throw …`, or Python's `assert …`.
    public let guarded: [String]

    private enum CodingKeys: String, CodingKey {
        case name, line, kind, supertypes, fields, methods, refused, empty, overrides, refusedOwn, emptyOwn, guarded
    }

    /// Every method whose body only throws or traps, `override` or not.
    public var allRefused: [String] { refused + refusedOwn }

    /// Every method whose body is empty, `override` or not.
    public var allEmpty: [String] { empty + emptyOwn }

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
        (refused, empty) = (members.refused, members.empty)
        (overrides, refusedOwn) = (members.overrides, members.refusedOwn)
        (emptyOwn, guarded) = (members.emptyOwn, members.guarded)
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
        (overrides, refusedOwn) = (try list(.overrides), try list(.refusedOwn))
        (emptyOwn, guarded) = (try list(.emptyOwn), try list(.guarded))
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
        let lists: [(CodingKeys, [String])] = [(.supertypes, supertypes), (.fields, fields), (.methods, methods),
            (.refused, refused), (.empty, empty), (.overrides, overrides), (.refusedOwn, refusedOwn),
            (.emptyOwn, emptyOwn), (.guarded, guarded)]
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
    public var overrides: [String] = []
    public var refusedOwn: [String] = []
    public var emptyOwn: [String] = []
    public var guarded: [String] = []

    /// Creates a member list; the Swift-only lists and `guarded` start empty.
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
    /// The type it's a method of (a Go method's receiver type), or `nil` for a free function.
    public let owner: String?
    /// Its return type as written without whitespace, or `nil` if none is written.
    public let returns: String?

    /// Creates a function fact.
    ///
    /// - Parameters:
    ///   - name: The function's name.
    ///   - line: The 1-indexed line of the declaration.
    ///   - parameters: Its parameters.
    ///   - owner: The type it's a method of, if any.
    ///   - returns: Its written return type, if any.
    public init(name: String, line: Int, parameters: [String] = [], owner: String? = nil, returns: String? = nil) {
        self.name = name
        self.line = line
        self.parameters = parameters
        self.owner = owner
        self.returns = returns.map { $0.filter { !$0.isWhitespace } }.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// What one type's code (or one extension's) does with other types: the members it reads on values whose
/// type is written, and the types it constructs and keeps. Both lists are sorted and distinct.
public struct CollaborationFact: Codable, Sendable, Equatable {
    /// The most entries kept per list, which bounds the cache for very large types.
    public static let maxEntries = 64
    /// The type, or the extended type for an extension.
    public let owner: String
    /// The 1-indexed line of the type's (or extension's) declaration.
    public let line: Int
    /// Members read on a parameter, property, or local whose type is written or constructed, as `Type.member`.
    public let uses: [String]
    /// Types constructed by name and kept in a property, such as `let api = Foo()`, `this.api = new Foo()`, or
    /// Python `self.api = Foo()`.
    public let constructs: [String]

    private enum CodingKeys: String, CodingKey { case owner, line, uses, constructs }

    /// Creates a collaboration fact, sorting and de-duplicating its lists and keeping at most `maxEntries` each.
    ///
    /// - Parameters:
    ///   - owner: The type.
    ///   - line: Its declaration's line.
    ///   - uses: Members read on typed values, as `Type.member`.
    ///   - constructs: Types constructed and kept in a property.
    public init(owner: String, line: Int, uses: [String] = [], constructs: [String] = []) {
        self.owner = owner
        self.line = line
        self.uses = Array(Set(uses).sorted().prefix(Self.maxEntries))
        self.constructs = Array(Set(constructs).sorted().prefix(Self.maxEntries))
    }

    /// Decodes a collaboration fact, treating a missing list as empty.
    ///
    /// - Parameter decoder: The decoder.
    /// - Throws: If a field is missing or malformed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        owner = try container.decode(String.self, forKey: .owner)
        line = try container.decode(Int.self, forKey: .line)
        uses = try container.decodeIfPresent([String].self, forKey: .uses) ?? []
        constructs = try container.decodeIfPresent([String].self, forKey: .constructs) ?? []
    }

    /// Encodes a collaboration fact, leaving out empty lists.
    ///
    /// - Parameter encoder: The encoder.
    /// - Throws: If encoding fails.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(owner, forKey: .owner)
        try container.encode(line, forKey: .line)
        try container.encodeNonEmpty(uses, forKey: .uses)
        try container.encodeNonEmpty(constructs, forKey: .constructs)
    }
}

/// Gathers one type's collaboration facts while an analyzer walks its declaration: which names hold which
/// types, which members are read on which names, and which types are constructed.
///
/// Bindings aren't scoped: a name bound to two different types anywhere in the type is ambiguous and its
/// reads are dropped. Standard-library types are never bound or recorded.
public final class CollaborationBuilder {
    private let owner: String
    private let line: Int
    private var bindings: [String: Set<String>] = [:]
    private var reads: Set<[String]> = []
    private var constructed: Set<String> = []
    private var properties: Set<String> = []
    private var assigned: Set<[String]> = []

    /// Starts gathering a type's facts.
    ///
    /// - Parameters:
    ///   - owner: The type, or the extended type for an extension.
    ///   - line: Its declaration's line.
    public init(owner: String, line: Int) {
        self.owner = owner
        self.line = line
    }

    /// Notes that a name holds a value of a type.
    ///
    /// - Parameters:
    ///   - name: A parameter, property, or local.
    ///   - type: The value's bare type name.
    public func bind(_ name: String, _ type: String) {
        guard name != "_", FactText.isProjectTypeCandidate(type) else { return }
        bindings[name, default: []].insert(type)
    }

    /// Notes a member read on a name.
    ///
    /// - Parameters:
    ///   - base: The name the member is read on.
    ///   - member: The member.
    public func access(_ base: String, _ member: String) { reads.insert([base, member]) }

    /// Notes a type constructed by name and kept in a property.
    ///
    /// - Parameter type: The type's bare name.
    public func construct(_ type: String) {
        if FactText.isProjectTypeCandidate(type), type != owner { constructed.insert(type) }
    }

    /// Notes a stored property's name, so a bare `name = Foo()` assigns it.
    ///
    /// - Parameter name: The property.
    public func property(_ name: String) { properties.insert(name) }

    /// Notes `name = Foo()` with a bare name, which keeps `Foo` if `name` turns out to be a property.
    ///
    /// - Parameters:
    ///   - name: The assigned name.
    ///   - type: The constructed type's bare name.
    public func assign(_ name: String, _ type: String) { assigned.insert([name, type]) }

    /// The gathered facts, resolving each read through the name's one bound type.
    ///
    /// - Returns: The facts, or `nil` if there are none.
    public var fact: CollaborationFact? {
        let uses = reads.compactMap { read -> String? in
            guard let types = bindings[read[0]], types.count == 1, let type = types.first, type != owner else {
                return nil
            }
            return type + "." + read[1]
        }
        let kept = assigned.filter { properties.contains($0[0]) && FactText.isProjectTypeCandidate($0[1]) }
        let constructs = constructed.union(kept.map { $0[1] }).subtracting([owner])
        guard !uses.isEmpty || !constructs.isEmpty else { return nil }
        return CollaborationFact(owner: owner, line: line, uses: uses, constructs: Array(constructs))
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
        let header = SourceFile.lines(of: contents).prefix(10)
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

    /// Reports whether code mentions any of some names as a whole identifier.
    ///
    /// - Parameters:
    ///   - code: The code, such as a condition.
    ///   - names: The names, such as a function's parameters.
    /// - Returns: Whether an identifier in `code` is one of `names`.
    public static func mentions(_ code: String, anyOf names: Set<String>) -> Bool {
        let identifiers = code.split { !($0.isLetter || $0.isNumber || $0 == "_") }.map(String.init)
        return identifiers.contains(where: names.contains)
    }

    /// Reports whether an error or message says an operation is unsupported or unimplemented, such as
    /// `UnsupportedOperation`, `"not supported"`, or `NotImplementedError`.
    ///
    /// - Parameter code: The `throw` or `raise` statement.
    /// - Returns: Whether it refuses rather than fails.
    public static func saysUnsupported(_ code: String) -> Bool {
        let flat = code.lowercased().filter { $0.isLetter }
        return ["unsupported", "notsupported", "notimplemented", "unimplemented", "unavailable"].contains {
            flat.contains($0)
        }
    }

    /// Capitalized standard-library and platform types, which are never project types.
    private static let libraryTypes: Set<String> = [
        "Any", "AnyObject", "Array", "Bool", "Character", "Data", "Date", "Decimal", "Dict", "Dictionary", "Double",
        "Error", "Float", "Int", "List", "Map", "Never", "Object", "Optional", "Promise", "Record", "Result", "Self",
        "Set", "String", "Substring", "Tuple", "Type", "UUID", "URL", "Union", "Void"
    ]

    /// Reports whether a bare type name could name a project type: capitalized and not a standard-library type.
    ///
    /// - Parameter name: The bare type name.
    /// - Returns: Whether collaboration facts should keep it.
    public static func isProjectTypeCandidate(_ name: String) -> Bool {
        name.first?.isUppercase == true && !libraryTypes.contains(name)
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
