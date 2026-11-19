import Foundation

/// A broad kind of built-in type, shared across languages, for the type-aware naming rules.
enum TypeCategory: Sendable {
    case boolean
    case string
    case integer
    case float
    case array
    case dictionary
    case set
}

/// Classifies type text (`[User]`, `boolean`, `Dict[str, int]`, `map[string]int`) and the
/// type words names end in (`userList`, `name_str`), for `boolean-name-prefix` and `type-in-name`.
enum TypeWords {
    private static let exactTypes: [String: Set<TypeCategory>] = {
        var table: [String: Set<TypeCategory>] = ["number": [.integer, .float]]
        let groups: [(TypeCategory, [String])] = [
            (.boolean, ["Bool", "boolean", "bool", "Boolean"]),
            (.string, ["String", "string", "str", "Substring"]),
            (.integer, integerTypes),
            (.float, ["Double", "Float", "CGFloat", "Float32", "Float64", "float", "float32", "float64"]),
            (.array, ["Array", "list", "List"]),
            (.dictionary, ["Dictionary", "dict", "Dict", "Map", "defaultdict", "OrderedDict"]),
            (.set, ["Set", "set", "frozenset"])
        ]
        for (category, names) in groups { names.forEach { table[$0] = [category] } }
        return table
    }()

    private static let integerTypes = ["Int", "UInt", "int", "uint", "bigint", "Integer"]
        + [8, 16, 32, 64].flatMap { ["Int\($0)", "UInt\($0)", "int\($0)", "uint\($0)"] }

    private static let genericPrefixes: [(String, TypeCategory)] = [
        ("Array<", .array), ("ReadonlyArray<", .array), ("ContiguousArray<", .array), ("List[", .array),
        ("list[", .array), ("Dictionary<", .dictionary), ("Map<", .dictionary), ("ReadonlyMap<", .dictionary),
        ("Record<", .dictionary), ("Dict[", .dictionary), ("dict[", .dictionary), ("defaultdict[", .dictionary),
        ("map[", .dictionary), ("Set<", .set), ("ReadonlySet<", .set), ("Set[", .set), ("set[", .set),
        ("frozenset[", .set)
    ]

    private static let suffixes: [String: TypeCategory] = [
        "list": .array, "array": .array, "string": .string, "str": .string, "int": .integer,
        "integer": .integer, "dict": .dictionary, "dictionary": .dictionary, "map": .dictionary, "set": .set,
        "bool": .boolean, "boolean": .boolean, "double": .float, "float": .float
    ]

    /// Classifies a declared or inferred type.
    ///
    /// - Parameter typeName: The type's source text, such as `[String: Int]?` or `: boolean`.
    /// - Returns: The categories it belongs to; `number` is both integer and float. Empty if unknown.
    static func categories(of typeName: String?) -> Set<TypeCategory> {
        guard let text = typeName.map(normalized), !text.isEmpty else { return [] }
        if let exact = exactTypes[text] { return exact }
        if text.hasPrefix("[]") || (text.hasSuffix("[]") && !text.hasPrefix("[")) { return [.array] }
        if text.hasPrefix("[") { return hasTopLevelColon(text) ? [.dictionary] : [.array] }
        return genericPrefixes.first { text.hasPrefix($0.0) }.map { [$0.1] } ?? []
    }

    /// Finds the type word a name ends in, as its own camelCase or snake_case word.
    ///
    /// - Parameter name: The declared name, such as `userList` or `name_str`.
    /// - Returns: The suffix as written and its category, or `nil` if the name has no type-word suffix.
    static func typeSuffix(of name: String) -> (word: String, category: TypeCategory)? {
        let word = lastWord(of: name)
        guard let word, word.count < name.count, let category = suffixes[word.lowercased()] else { return nil }
        return (word, category)
    }

    /// Strips what doesn't change a type's category: a TS `:` annotation prefix, optionality, and
    /// `null`/`undefined`/`None` union members.
    ///
    /// - Parameter typeName: The raw type text.
    /// - Returns: The core type text.
    private static func normalized(_ typeName: String) -> String {
        var text = typeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(":") { text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces) }
        if text.hasPrefix("Optional["), text.hasSuffix("]") { text = String(text.dropFirst(9).dropLast()) }
        let members = text.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !["null", "undefined", "None"].contains($0) }
        if members.count == 1, let only = members.first { text = only }
        while let last = text.last, last == "?" || last == "!" { text.removeLast() }
        return text
    }

    /// Reports whether a bracketed Swift type is a dictionary, `[K: V]`, rather than an array.
    ///
    /// - Parameter text: The type text, starting with `[`.
    /// - Returns: Whether a `:` sits directly inside the outer brackets.
    private static func hasTopLevelColon(_ text: String) -> Bool {
        var depth = 0
        for character in text {
            if "[<(".contains(character) { depth += 1 } else if "]>)".contains(character) { depth -= 1 }
            if character == ":", depth == 1 { return true }
        }
        return false
    }

    /// Splits a camelCase or snake_case name into lowercase words.
    ///
    /// - Parameter name: The name, such as `isReady`, `is_ready`, or `_isReady`.
    /// - Returns: Its words, such as `["is", "ready"]`.
    static func words(of name: String) -> [String] {
        let spaced = name.map { character -> String in
            if character == "_" || character == "$" { return " " }
            return character.isUppercase ? " \(character)" : String(character)
        }.joined()
        return spaced.split(separator: " ").map { $0.lowercased() }
    }

    /// Splits off a name's last word: after its last `_`, or from its last uppercase letter on.
    ///
    /// - Parameter name: The name.
    /// - Returns: The last word, or `nil` if the name is a single word.
    private static func lastWord(of name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: "_$"))
        if let underscore = trimmed.lastIndex(of: "_") { return String(trimmed[trimmed.index(after: underscore)...]) }
        guard let upper = trimmed.lastIndex(where: \.isUppercase), upper != trimmed.startIndex else { return nil }
        return String(trimmed[upper...])
    }
}
