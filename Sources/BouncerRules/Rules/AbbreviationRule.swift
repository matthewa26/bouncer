import Foundation
import BouncerCore

/// Flags a declared name containing a known abbreviation, such as `usrMgr` or `btn_cnt`, and suggests the word.
///
/// Opt-in. Names are read from declarations by keyword (`let`, `var`, `const`, `func`, `function`, `def`, `class`,
/// `struct`, `enum`, `protocol`, `interface`, `type`, `case`), Go's `:=`, and Python's unindented `name =`, on code
/// lines with strings blanked; parameters and uses aren't checked. Each name is split into camelCase and snake_case
/// words, and a word on the denylist (`mgr`, `usr`, `btn`, `cnt`, `msg`, `cfg`, `req`, `resp`, `ctx`, `idx`, `num`,
/// `val`, `str`, `arr`, `obj`, `elem`, `ptr`, `addr`, `tmp`, `pwd`, `img`, `desc`, `evt`, `prev`, `cur`, `attr`, …)
/// is flagged unless the language's idioms allow it (Go allows `ctx`, `req`, `resp`, `cfg`, `msg`, `buf`, `elem`,
/// and friends; JavaScript `req`, `res`, `ctx`, `prev`; C and C++ `ptr`, `len`, `str`, `tmp`, `idx`). `objC` reads
/// as a name, not an abbreviation, and compiler jargon (`expr`, `decl`, `stmt`) isn't on the default list. The
/// `allow` parameter adds words to accept; `deny` adds words to flag, as `word` or `word=expansion`. One finding per
/// declaration, naming its first abbreviation.
public struct AbbreviationRule: Rule {
    public static let ruleID = "abbreviation"
    public let id = AbbreviationRule.ruleID
    /// Words that, with the word after them, form a proper name rather than an abbreviation.
    private static let properNames: Set = ["objc"]
    private static let declaration = TextMatching.regex(
        #"\b(?:let|var|const|func|function|def|class|struct|enum|protocol|interface|type|case)\s+([A-Za-z_$][\w$]*)"#
            + #"|\b([A-Za-z_]\w*)(?:\s*,\s*[A-Za-z_]\w*)*\s*:=|^([a-z_]\w*)\s*=(?!=)"#
    )

    /// Creates the rule.
    public init() {}

    /// Flags each declaration whose name uses an abbreviation that isn't allowed.
    ///
    /// Runs only when `.bouncer` enables it explicitly.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's `allow` and `deny` parameters.
    /// - Returns: One finding per flagged declaration.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        guard let settings = SourceText.optInSettings(id, context) else { return [] }
        let words = Abbreviations.denied(for: file.language, parameters: settings.parameters)
        return SourceText.flagCodeLines(id, settings, file) { index in
            guard let (name, word) = Self.abbreviated(in: file.lines[index], words) else { return nil }
            let expansion = words[word].flatMap { $0.isEmpty ? nil : " ('\($0)')" } ?? ""
            return "'\(name)' uses the abbreviation '\(word)'; spell it out\(expansion)."
        }
    }

    /// Finds the first declared name on a line with a denied word.
    ///
    /// - Parameters:
    ///   - line: The line to read.
    ///   - denied: The denied words and their expansions.
    /// - Returns: The name and its abbreviated word, or `nil`.
    private static func abbreviated(in line: Substring, _ denied: [String: String]) -> (String, String)? {
        let names = TextMatching.captures(declaration, SourceText.code(of: line)).compactMap { match in
            match.dropFirst().first { !$0.isEmpty }
        }
        return names.lazy.compactMap { name in abbreviation(in: name, denied).map { (name, $0) } }.first
    }

    /// Finds the first denied word in a name, skipping one that's part of a proper name (`objC`).
    ///
    /// - Parameters:
    ///   - name: The declared name.
    ///   - denied: The denied words and their expansions.
    /// - Returns: The abbreviated word, or `nil`.
    private static func abbreviation(in name: String, _ denied: [String: String]) -> String? {
        let words = SourceText.words(of: name)
        let index = words.indices.first { index in
            let next = index + 1 < words.count ? words[index + 1] : ""
            return denied[words[index]] != nil && !properNames.contains(words[index] + next)
        }
        return index.map { words[$0] }
    }
}

/// The abbreviation lists `AbbreviationRule` checks names against.
enum Abbreviations {
    private static let defaults: [String: String] = [
        "mgr": "manager", "mngr": "manager", "usr": "user", "btn": "button", "cnt": "count", "msg": "message",
        "cfg": "configuration", "conf": "configuration", "req": "request", "resp": "response", "ctx": "context",
        "idx": "index", "num": "number", "val": "value", "str": "string", "arr": "array", "obj": "object",
        "elem": "element", "ptr": "pointer", "addr": "address", "srv": "server", "svc": "service",
        "tmp": "temporary", "calc": "calculate", "pwd": "password", "img": "image", "pkg": "package", "lbl": "label",
        "txt": "text", "desc": "description", "evt": "event", "prev": "previous", "curr": "current", "cur": "current",
        "attr": "attribute", "ctrl": "controller",
        "acct": "account", "amt": "amount", "qty": "quantity", "len": "length", "buf": "buffer", "res": "result"
    ]
    private static let idioms: [Language: Set<String>] = [
        .go: ["ctx", "req", "resp", "res", "cfg", "msg", "srv", "addr", "ptr", "idx", "num", "str", "val", "tmp", "len",
              "buf", "pkg", "elem"],
        .javascript: ["req", "res", "ctx", "prev", "cur", "curr", "evt", "idx", "val", "obj", "arr", "len"],
        .typescript: ["req", "res", "ctx", "prev", "cur", "curr", "evt", "idx", "val", "obj", "arr", "len"],
        .python: ["ctx", "req", "resp", "tmp", "idx", "len", "buf"],
        .c: ["ptr", "len", "str", "tmp", "idx", "num", "val", "cnt", "buf", "addr", "ctx", "cur", "prev", "res"],
        .cpp: ["ptr", "len", "str", "tmp", "idx", "num", "val", "cnt", "buf", "addr", "ctx", "cur", "prev", "res"],
        .objc: ["ptr", "len", "str", "tmp", "idx", "num", "val", "cnt", "buf", "addr", "ctx", "cur", "prev", "res"]
    ]

    /// Builds the denied words for a language: the defaults and `deny`, less the language's idioms and `allow`.
    ///
    /// - Parameters:
    ///   - language: The file's language.
    ///   - parameters: The rule's parameters.
    /// - Returns: Each denied word (lowercased) and its expansion, if known.
    static func denied(for language: Language, parameters: RuleParameters) -> [String: String] {
        let extra = parameters.stringList("deny", default: []).compactMap(denyEntry)
        let configured = parameters.stringList("allow", default: []).map { $0.lowercased() }
        let allowed = (idioms[language] ?? []).union(configured)
        let merged = defaults.merging(extra) { old, new in new.isEmpty ? old : new }
        return merged.filter { !allowed.contains($0.key) }
    }

    /// Splits a `deny` entry, `word` or `word=expansion`.
    ///
    /// - Parameter entry: The configured entry.
    /// - Returns: The lowercased word and its expansion (empty if none), or `nil` for an empty entry.
    private static func denyEntry(_ entry: String) -> (String, String)? {
        let parts = entry.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let word = parts.first, !word.isEmpty else { return nil }
        return (word.lowercased(), parts.count > 1 ? parts[1] : "")
    }
}
