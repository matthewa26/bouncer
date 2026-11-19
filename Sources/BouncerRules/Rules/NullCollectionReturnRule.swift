import Foundation
import BouncerCore

/// Flags a function whose declared return type is an optional or nullable collection and whose body returns
/// `nil`, `null`, `undefined`, or `None`, where an empty collection would spare every caller an unwrap.
///
/// It reads signatures as text: Swift `-> [T]?`, `-> [K: V]?`, `-> Set<T>?`; TypeScript `): T[] | null`,
/// `Array<T> | undefined`, `Map<K, V> | null`; Python `-> Optional[List[T]]` or `-> list[T] | None`; Java methods
/// returning a `List`, `Set`, `Map`, `Collection`, or array. A `return` of the null value counts directly or as
/// either arm of a conditional (`return list.isEmpty ? nil : list`), but only in the function's own body, not in a
/// closure, lambda, or nested function inside it; an implicit return (a single-expression body) isn't read.
///
/// Opt-in, since a null collection often means something an empty one can't (not loaded, unsupported, failed).
/// Two signs of that leave a function alone: it also returns an empty collection somewhere, or the comment above
/// it (or, in Python, its docstring) names the null value, as in "or `nil` if the file is missing". Go is skipped,
/// where a nil slice or map already reads as empty, and so are test files.
public struct NullCollectionReturnRule: Rule {
    public static let ruleID = "null-collection-return"
    public let id = NullCollectionReturnRule.ruleID

    /// Creates the rule.
    public init() {}

    /// Flags each function that returns a null value for its optional collection type.
    ///
    /// Runs only when `.bouncer` enables it explicitly.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per such function, on the line that declares its return type.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        guard let settings = SourceText.optInSettings(id, context), let syntax = NullCollectionSyntax.of(file.language),
              !TextMatching.isTestPath(file.path) else { return [] }
        let message = "Returns \(syntax.nullWord) for an optional collection; return an empty collection and drop "
            + "the optional, unless \(syntax.nullWord) means something different from empty."
        return SourceText.flagCodeLines(id, settings, file) { index in
            syntax.returnsNull(fromSignatureAt: index, in: file) ? message : nil
        }
    }
}

/// One language's view of a nullable-collection function: how its signature, null return, and empty return read.
struct NullCollectionSyntax {
    /// The language's null value, for messages.
    let nullWord: String
    /// Matches a line declaring a function's return type, capturing the type.
    let signature: NSRegularExpression?
    /// Matches a statement returning the null value.
    let nullReturn: NSRegularExpression?
    /// Matches a statement returning an empty collection.
    let emptyReturn: NSRegularExpression?
    /// Reports whether a captured return type is a nullable collection.
    let isNullableCollection: @Sendable (String) -> Bool
    /// The keyword that must start a split signature (`func`, `def`), or `nil` where the signature line suffices.
    let keyword: String?
    /// Matches the null value named in a doc comment.
    let nullMention: NSRegularExpression?
    /// Whether the body is indented (Python) rather than braced.
    let indented: Bool

    /// Looks up a language's syntax.
    ///
    /// - Parameter language: The file's language.
    /// - Returns: The syntax, or `nil` for a language the rule skips.
    static func of(_ language: Language) -> NullCollectionSyntax? {
        let syntaxes: [Language: NullCollectionSyntax] = [
            .swift: NullCollectionLanguages.swift, .typescript: NullCollectionLanguages.typeScript,
            .python: NullCollectionLanguages.python, .java: NullCollectionLanguages.java
        ]
        return syntaxes[language]
    }

    /// Reports whether a line declares a nullable-collection function whose own body returns the null value and
    /// never an empty collection.
    ///
    /// - Parameters:
    ///   - index: The line's 0-based index.
    ///   - file: The file it's in.
    /// - Returns: Whether the function should return an empty collection instead.
    func returnsNull(fromSignatureAt index: Int, in file: SourceFile) -> Bool {
        let code = SourceText.code(of: file.lines[index])
        guard let type = TextMatching.captures(signature, code).first?[1], isNullableCollection(type),
              let start = declarationStart(at: index, in: file) else { return false }
        let body = indented ? NullCollectionBody.indentedLines(after: index, in: file)
            : NullCollectionBody.bracedLines(after: index, in: file)
        guard body.contains(where: { TextMatching.matches(nullReturn, $0) }),
              !body.contains(where: { TextMatching.matches(emptyReturn, $0) }) else { return false }
        return !NullCollectionDocs.mention(nullMention, before: start, after: indented ? index : nil, in: file)
    }

    /// Finds the line a function's declaration starts on. For Swift and Python that's the `func` or `def` line, on
    /// the signature line or one of the few above it (a signature split over lines) with no block opened or closed
    /// in between; elsewhere it's the first line of a parameter list continued onto the signature line.
    ///
    /// - Parameters:
    ///   - index: The signature's 0-based line index.
    ///   - file: The file it's in.
    /// - Returns: The 0-based start line, or `nil` if no function declares the signature.
    private func declarationStart(at index: Int, in file: SourceFile) -> Int? {
        guard let keyword else { return NullCollectionDocs.continuedStart(of: index, in: file) }
        let pattern = TextMatching.regex(#"^\s*(?:@\w+\s+)*(?:[\w()]+\s+)*"# + keyword + #"\s"#)
        for offset in 0..<NullCollectionLanguages.maxSignatureLines where index - offset >= 0 {
            let line = SourceText.code(of: file.lines[index - offset])
            if TextMatching.matches(pattern, line) { return index - offset }
            if offset > 0 && (line.contains("{") || line.contains("}") || line.hasSuffix(":")) { return nil }
        }
        return nil
    }
}

/// Reads the documentation around a function's declaration, where an author says what a null result means.
enum NullCollectionDocs {
    private static let commentLine = TextMatching.regex(#"^\s*(?:///?|/\*\*?|\*|#)"#)
    private static let attributeLine = TextMatching.regex(#"^\s*@\w+"#)
    private static let docstringOpen = TextMatching.regex(#"^\s*[rRuUbB]?(?:"""|''')"#)

    /// Reports whether the comment above a declaration, or (for Python) the docstring below its signature, mentions
    /// the null value: then the null value is a documented result with its own meaning, not a stand-in for empty.
    ///
    /// - Parameters:
    ///   - mention: Matches the language's null value in prose.
    ///   - start: The declaration's first 0-based line.
    ///   - signatureEnd: For Python, the line ending the signature, whose docstring follows; otherwise `nil`.
    ///   - file: The file.
    /// - Returns: Whether the documentation names the null value.
    static func mention(_ mention: NSRegularExpression?, before start: Int, after signatureEnd: Int?,
                        in file: SourceFile) -> Bool {
        let above = file.lines[..<start].reversed().prefix { line in
            TextMatching.matches(commentLine, line) || TextMatching.matches(attributeLine, line)
        }
        let below = signatureEnd.map { docstring(after: $0, in: file) } ?? []
        return (Array(above) + below).contains { TextMatching.matches(mention, $0) }
    }

    /// Reads the docstring that opens a Python function body, if there is one.
    ///
    /// - Parameters:
    ///   - index: The 0-based line ending the signature.
    ///   - file: The file.
    /// - Returns: The docstring's lines, or none.
    private static func docstring(after index: Int, in file: SourceFile) -> [Substring] {
        let lines = file.lines.dropFirst(index + 1).drop { $0.allSatisfy(\.isWhitespace) }
        guard let first = lines.first, TextMatching.matches(docstringOpen, first) else { return [] }
        let quote = first.contains("\"\"\"") ? "\"\"\"" : "'''"
        let closesOnFirst = first.components(separatedBy: quote).count > 2
        let rest = closesOnFirst ? [] : Array(lines.dropFirst().prefix { !$0.contains(quote) })
        return [first] + rest
    }

    /// Finds where a parameter list continued onto a signature line starts: lines above it that end with `(` or `,`
    /// belong to the same declaration.
    ///
    /// - Parameters:
    ///   - index: The signature's 0-based line.
    ///   - file: The file.
    /// - Returns: The declaration's first 0-based line.
    static func continuedStart(of index: Int, in file: SourceFile) -> Int {
        var start = index
        while start > 0, index - start < NullCollectionLanguages.maxSignatureLines,
              let last = SourceText.code(of: file.lines[start - 1]).trimmingCharacters(in: .whitespaces).last,
              last == "(" || last == "," {
            start -= 1
        }
        return start
    }
}

/// The per-language patterns `NullCollectionReturnRule` reads.
enum NullCollectionLanguages {
    /// The most lines a split signature is followed back to its `func` or `def`.
    static let maxSignatureLines = 12
    private static let swiftCollection = TextMatching.regex(
        #"^(?:\[.+\]|(?:Set|Array|Dictionary|ContiguousArray|ArraySlice|OrderedSet|OrderedDictionary)<.+>)\?$"#
    )
    private static let pythonCollection = #"(?:List|list|Dict|dict|Set|set|FrozenSet|frozenset|Sequence|"#
        + #"Mapping|MutableMapping|MutableSequence|Iterable|Collection|Deque|deque)\[.*\]"#
    private static let pythonNullable = TextMatching.regex(
        #"^(?:(?:typing\.)?Optional\["# + pythonCollection + #"\]|"# + pythonCollection + #"\s*\|\s*None|"#
            + #"None\s*\|\s*"# + pythonCollection + #"|(?:typing\.)?Union\["# + pythonCollection + #",\s*None\])$"#
    )
    private static let scriptCollection = TextMatching.regex(
        #"^(?:readonly\s+)?(?:[\w$.]+(?:<.*>)?|\(.*\))\[\]$|^(?:Readonly)?(?:Array|Map|Set|ReadonlyArray)<.*>$"#
    )

    static let swift = NullCollectionSyntax(
        nullWord: "nil",
        signature: TextMatching.regex(#"\)\s*(?:async\s+)?(?:(?:re)?throws(?:\([^)]*\))?\s+)?->\s*(.+?)\s*"#
            + #"(?:where\b[^{]*)?\{\s*$"#),
        nullReturn: returning(null: "nil"),
        emptyReturn: returning(empty: #"\[\s*:?\s*\]|\.init\(\)|\[[^\]]+\]\(\)|"#
            + #"(?:Set|Array|Dictionary|ContiguousArray|OrderedSet|OrderedDictionary)(?:<[^>]*>)?\(\)"#),
        isNullableCollection: { TextMatching.matches(swiftCollection, $0) }, keyword: "func",
        nullMention: TextMatching.regex(#"\bnil\b"#), indented: false
    )
    static let typeScript = NullCollectionSyntax(
        nullWord: "null", signature: TextMatching.regex(#"\)\s*:\s*([^{=]+?)\s*(?:=>\s*)?\{\s*$"#),
        nullReturn: returning(null: "null|undefined"),
        emptyReturn: returning(empty: #"\[\s*\]|new\s+(?:Map|Set|Array)(?:<[^>]*>)?\(\s*\)"#),
        isNullableCollection: scriptNullable, keyword: nil,
        nullMention: TextMatching.regex(#"\b(?:null|undefined)\b"#), indented: false
    )
    static let python = NullCollectionSyntax(
        nullWord: "None", signature: TextMatching.regex(#"\)\s*->\s*(.+?)\s*:\s*(?:#.*)?$"#),
        nullReturn: TextMatching.regex(#"^\s*return\s+None\s*(?:#.*)?$|^\s*return\b.*\belse\s+None\s*(?:#.*)?$"#),
        emptyReturn: returning(empty: #"\[\s*\]|\{\s*\}|\(\s*\)|(?:set|list|dict|tuple)\(\)"#),
        isNullableCollection: { TextMatching.matches(pythonNullable, $0) }, keyword: "def",
        nullMention: TextMatching.regex(#"\bNone\b"#), indented: true
    )
    static let java = NullCollectionSyntax(
        nullWord: "null",
        signature: TextMatching.regex(#"^\s*(?:(?:public|private|protected|static|final|synchronized)\s+)*"#
            + #"(?:<[^>]+>\s+)?((?:[\w.]+(?:<.*>)?\[\])|(?:(?:java\.util\.)?(?:List|ArrayList|LinkedList|Set|"#
            + #"HashSet|TreeSet|SortedSet|Map|HashMap|TreeMap|SortedMap|Collection|Iterable)(?:<.*>)?))\s+\w+\s*\("#),
        nullReturn: returning(null: "null"),
        emptyReturn: returning(empty: #"new\s+[\w.]+(?:<[^>]*>)?(?:\(\s*\)|\[\s*0\s*\]|\[\]\s*\{\s*\})|"#
            + #"(?:List|Set|Map)\.of\(\)|Collections\.empty\w*\(\)"#),
        isNullableCollection: { _ in true }, keyword: nil,
        nullMention: TextMatching.regex(#"\bnull\b"#), indented: false
    )

    /// Builds the pattern for a statement that returns the null value, directly or from either arm of a
    /// conditional expression (`return list.isEmpty ? nil : list`).
    ///
    /// - Parameter null: The language's null values, as alternatives.
    /// - Returns: The compiled pattern.
    private static func returning(null: String) -> NSRegularExpression? {
        TextMatching.regex(#"\breturn\s+(?:"# + null + #")\b|\breturn\b.*\?\s*(?:"# + null + #")\s*:|"#
            + #"\breturn\b.*\s:\s*(?:"# + null + #")\s*;?\s*(?://.*)?$"#)
    }

    /// Builds the pattern for a statement that returns an empty collection, directly or as part of an expression
    /// (`return tags ?? []`), but not one used as a receiver or argument (`return [:].merging(…)`).
    ///
    /// - Parameter empty: The language's empty collections, as alternatives.
    /// - Returns: The compiled pattern.
    private static func returning(empty: String) -> NSRegularExpression? {
        TextMatching.regex(#"\breturn\b(?:[^;\n]*[\s?:=])?(?:"# + empty + #")(?![\w.(\[])"#)
    }

    /// Reports whether a TypeScript return type is a collection joined with `null` or `undefined`.
    ///
    /// - Parameter type: The return type, such as `string[] | null`.
    /// - Returns: Whether it's a nullable array, `Map`, or `Set`.
    private static func scriptNullable(_ type: String) -> Bool {
        let parts = type.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        let rest = parts.filter { $0 != "null" && $0 != "undefined" }
        guard parts.count > rest.count, rest.count == 1 else { return false }
        return TextMatching.matches(scriptCollection, rest[0])
    }
}

/// Collects the lines of a function body that belong to the function itself, leaving out nested closures,
/// lambdas, and functions, whose `return` statements return from them instead.
enum NullCollectionBody {
    private static let control = TextMatching.regex(
        #"^(?:if|else|guard|for|while|switch|do|catch|repeat|defer|try|finally|synchronized|case|default)\b|"#
            + #"\belse\s*$|^$"#
    )
    private static let nestedDef = TextMatching.regex(#"^\s*(?:async\s+)?def\s"#)

    /// Lists a braced function's own lines, from just after its opening brace to its closing brace, each cut
    /// short where a closure or nested function opens and resumed where it closes.
    ///
    /// - Parameters:
    ///   - index: The 0-based line holding the function's opening brace (or, for Java, its signature).
    ///   - file: The file.
    /// - Returns: The function's own code, one string per line; empty for a declaration with no body.
    static func bracedLines(after index: Int, in file: SourceFile) -> [String] {
        guard let (opening, rest) = openingBrace(from: index, in: file) else { return [] }
        let end = SourceText.blockEnd(from: opening, in: file)
        let following = opening < end ? file.lines[(opening + 1)...end].map { SourceText.code(of: $0) } : []
        var closures: [Bool] = []
        return ([rest] + following).map { ownCode($0, closures: &closures) }
    }

    /// Finds a function's opening brace: the first `{` from its signature on, unless a `;` ends the
    /// declaration first, as for an abstract or interface method.
    ///
    /// - Parameters:
    ///   - index: The signature's 0-based line.
    ///   - file: The file.
    /// - Returns: The brace's line and the code after it on that line, or `nil` for a declaration with no body.
    private static func openingBrace(from index: Int, in file: SourceFile) -> (Int, String)? {
        let last = min(file.lines.count - 1, index + NullCollectionLanguages.maxSignatureLines)
        for line in index...last {
            let code = SourceText.code(of: file.lines[line])
            guard let mark = code.firstIndex(where: { $0 == "{" || $0 == ";" }) else { continue }
            return code[mark] == "{" ? (line, String(code[code.index(after: mark)...])) : nil
        }
        return nil
    }

    /// Keeps the parts of a line outside any closure, tracking the blocks it opens and closes.
    ///
    /// - Parameters:
    ///   - code: The line's code, strings blanked.
    ///   - closures: Whether each block open at the line's start is a closure; updated past the line.
    /// - Returns: The line's text outside closures.
    private static func ownCode(_ code: String, closures: inout [Bool]) -> String {
        var kept = "", prefix = ""
        for char in code {
            if !closures.contains(true) { kept.append(char) }
            if char == "{" { closures.append(!isBlock(prefix)) }
            if char == "}" { _ = closures.popLast() }
            prefix.append(char)
        }
        return kept
    }

    /// Reports whether the text before a `{` on its line opens an ordinary block, rather than a closure, lambda,
    /// or nested function: it starts with a control keyword (after any closing braces) with its parentheses
    /// balanced, ends with `else`, or is empty, as for a brace on its own line.
    ///
    /// - Parameter prefix: The line's text before the brace.
    /// - Returns: Whether the brace opens a block.
    private static func isBlock(_ prefix: String) -> Bool {
        let statement = prefix.drop { $0.isWhitespace || $0 == "}" }.trimmingCharacters(in: .whitespaces)
        let opens = statement.filter { $0 == "(" }.count, closes = statement.filter { $0 == ")" }.count
        return opens == closes && TextMatching.matches(control, statement)
    }

    /// Lists an indented (Python) function's own lines after its signature, skipping nested `def` blocks.
    ///
    /// - Parameters:
    ///   - index: The 0-based line ending the function's signature.
    ///   - file: The file.
    /// - Returns: The function's own lines.
    static func indentedLines(after index: Int, in file: SourceFile) -> [String] {
        let body = file.lines.indices.dropFirst(index + 1)
        guard let first = body.first(where: { !file.lines[$0].allSatisfy(\.isWhitespace) }) else { return [] }
        let end = SourceText.indentedBlockEnd(after: first, in: file)
        let starts = sequence(first: first) { cursor -> Int? in
            let nested = TextMatching.matches(nestedDef, file.lines[cursor])
            let next = nested ? nestedEnd(after: cursor, in: file) + 1 : cursor + 1
            return next <= end ? next : nil
        }
        return starts.filter { !TextMatching.matches(nestedDef, file.lines[$0]) }.map { String(file.lines[$0]) }
    }

    /// Finds the last line of a nested `def`: its signature line, then its indented body.
    ///
    /// - Parameters:
    ///   - index: The nested `def`'s 0-based line.
    ///   - file: The file.
    /// - Returns: The 0-based last line of its body, or `index` if nothing follows it.
    private static func nestedEnd(after index: Int, in file: SourceFile) -> Int {
        let indent = file.lines[index].prefix(while: \.isWhitespace).count
        let body = file.lines.indices.dropFirst(index + 1).first { line in
            let text = file.lines[line]
            return !text.allSatisfy(\.isWhitespace) && text.prefix(while: \.isWhitespace).count > indent
        }
        return body.map { SourceText.indentedBlockEnd(after: $0, in: file) } ?? index
    }
}
