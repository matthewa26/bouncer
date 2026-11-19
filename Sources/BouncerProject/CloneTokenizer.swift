import BouncerCore

/// One normalized token: the hash of its normalized text, the line it starts on, and for an identifier the
/// hash of its actual name (otherwise 0), which tells whether two placeholders stand for the same name.
struct CloneToken: Equatable {
    let hash: UInt64
    let line: Int
    var name: UInt64 = 0
}

/// The comment and string syntax a language's tokens are read with.
struct CloneSyntax {
    let lineComment: [UInt8]
    let blockComment: (open: [UInt8], close: [UInt8])?
    let quotes: Set<UInt8>
    /// Whether `"""` (and `'''` where `'` quotes) opens a multi-line string.
    let tripleQuotes: Bool

    private static let slashes = Array("//".utf8), block = (open: Array("/*".utf8), close: Array("*/".utf8))
    private static let quote = UInt8(ascii: "\""), apostrophe = UInt8(ascii: "'"), backtick = UInt8(ascii: "`")
    private static let swift = CloneSyntax(
        lineComment: slashes, blockComment: block, quotes: [quote], tripleQuotes: true
    )
    /// TypeScript, JavaScript, and Go: `'` and `` ` `` quote too (runes, template and raw strings).
    private static let cFamily = CloneSyntax(
        lineComment: slashes, blockComment: block, quotes: [quote, apostrophe, backtick], tripleQuotes: false
    )
    private static let python = CloneSyntax(
        lineComment: Array("#".utf8), blockComment: nil, quotes: [quote, apostrophe], tripleQuotes: true
    )

    /// Looks up a language's syntax.
    ///
    /// - Parameter language: The file's language.
    /// - Returns: Its syntax, or `nil` for a language duplicate-code doesn't tokenize.
    static func of(_ language: Language) -> CloneSyntax? {
        switch language {
        case .swift: return swift
        case .typescript, .javascript, .go: return cFamily
        case .python: return python
        default: return nil
        }
    }
}

/// Splits source text into normalized tokens for clone detection, language-neutrally.
///
/// Whitespace and comments are dropped. Keywords and punctuation keep their text, every other identifier
/// becomes one placeholder (remembering its name, for consistent-renaming matching), and every string or
/// number literal becomes another (unless literals are kept), so a copy with renamed variables tokenizes the
/// same as the original. Punctuation is one token per character, which is consistent across copies and so
/// doesn't need per-language operator tables.
struct CloneTokenizer {
    private typealias Byte = CloneBytes
    private static let identifierHash = StableHash.value("ID".utf8)
    private static let literalHash = StableHash.value("LIT".utf8)
    private static let keywords = Set(CloneKeywords.all.map { StableHash.value($0.utf8) })

    private let bytes: [UInt8]
    private let syntax: CloneSyntax
    private let keepLiterals: Bool
    private var index = 0
    private var line = 1
    private var tokens: [CloneToken] = []

    /// Creates a tokenizer over one file's bytes.
    ///
    /// - Parameters:
    ///   - bytes: The file's UTF-8 contents.
    ///   - syntax: Its language's comment and string syntax.
    ///   - keepLiterals: Whether literals keep their values instead of becoming a placeholder.
    private init(bytes: [UInt8], syntax: CloneSyntax, keepLiterals: Bool) {
        self.bytes = bytes
        self.syntax = syntax
        self.keepLiterals = keepLiterals
    }

    /// Tokenizes a file.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - keepLiterals: Whether literals keep their values instead of becoming a placeholder.
    /// - Returns: Its normalized tokens, or `nil` for a language that isn't tokenized.
    static func tokens(of file: SourceFile, keepLiterals: Bool) -> [CloneToken]? {
        guard let syntax = CloneSyntax.of(file.language) else { return nil }
        var tokenizer = CloneTokenizer(bytes: Array(file.contents.utf8), syntax: syntax, keepLiterals: keepLiterals)
        while tokenizer.index < tokenizer.bytes.count { tokenizer.step() }
        return tokenizer.tokens
    }

    /// Consumes one piece of input: a newline, whitespace, a comment, or a token.
    private mutating func step() {
        let byte = bytes[index]
        if byte <= Byte.space {
            line += byte == Byte.newline ? 1 : 0
            index += 1
        } else if Self.isWordByte(byte) {
            readWord(startingWith: byte)
        } else if !skipComment() && !readString() {
            readPunctuation()
        }
    }

    /// Reads one punctuation character as its own token.
    private mutating func readPunctuation() {
        emit(StableHash.value(bytes[index...index]))
        index += 1
    }

    /// Reads an identifier, keyword, or number; a number may contain `.`, as in `1.5`.
    ///
    /// - Parameter first: The word's first byte.
    private mutating func readWord(startingWith first: UInt8) {
        let start = index, isNumber = Self.isDigit(first)
        while index < bytes.count, Self.isWordByte(bytes[index]) || (isNumber && bytes[index] == Byte.dot) {
            index += 1
        }
        let hash = StableHash.value(bytes[start..<index])
        if isNumber { return emitLiteral(hash) }
        if Self.keywords.contains(hash) { return emit(hash) }
        tokens.append(CloneToken(hash: Self.identifierHash, line: line, name: hash))
    }

    /// Skips a line or block comment at the current position.
    ///
    /// - Returns: Whether there was one.
    private mutating func skipComment() -> Bool {
        if matches(syntax.lineComment, at: index) {
            advance(to: bytes[index...].firstIndex(of: Byte.newline) ?? bytes.count)
            return true
        }
        guard let block = syntax.blockComment, matches(block.open, at: index) else { return false }
        advance(to: end(of: block.close, from: index + block.open.count))
        return true
    }

    /// Reads a string literal at the current position, single-line or triple-quoted.
    ///
    /// - Returns: Whether there was one.
    private mutating func readString() -> Bool {
        let quote = bytes[index], start = index, startLine = line
        guard syntax.quotes.contains(quote) else { return false }
        let triple = [quote, quote, quote]
        let isTriple = syntax.tripleQuotes && matches(triple, at: index)
        advance(to: isTriple ? end(of: triple, from: index + 3) : closingQuote(quote))
        emitLiteral(StableHash.value(bytes[start..<index]), line: startLine)
        return true
    }

    /// Finds the end of a single-line string; an unterminated one ends at the line break.
    ///
    /// - Parameter quote: The opening quote.
    /// - Returns: The index just past the closing quote.
    private func closingQuote(_ quote: UInt8) -> Int {
        var cursor = index + 1
        while cursor < bytes.count, bytes[cursor] != quote {
            if bytes[cursor] == Byte.newline && quote != UInt8(ascii: "`") { return cursor }
            cursor += bytes[cursor] == Byte.backslash ? 2 : 1
        }
        return min(cursor + 1, bytes.count)
    }

    /// Finds where a delimiter next ends, or the end of input if it never does.
    ///
    /// - Parameters:
    ///   - delimiter: The closing delimiter, such as `*/`.
    ///   - start: Where to start looking.
    /// - Returns: The index just past the delimiter.
    private func end(of delimiter: [UInt8], from start: Int) -> Int {
        var cursor = start
        while cursor + delimiter.count <= bytes.count {
            if matches(delimiter, at: cursor) { return cursor + delimiter.count }
            cursor += 1
        }
        return bytes.count
    }

    /// Reports whether a byte pattern occurs at a position.
    ///
    /// - Parameters:
    ///   - pattern: The bytes to look for.
    ///   - position: Where to look.
    /// - Returns: Whether they're there.
    private func matches(_ pattern: [UInt8], at position: Int) -> Bool {
        position + pattern.count <= bytes.count && bytes[position..<position + pattern.count].elementsEqual(pattern)
    }

    /// Moves to a later position, counting the line breaks skipped over.
    ///
    /// - Parameter end: The new position.
    private mutating func advance(to end: Int) {
        line += bytes[index..<end].reduce(0) { $0 + ($1 == Byte.newline ? 1 : 0) }
        index = end
    }

    /// Adds a literal token, normalized unless literals are kept.
    ///
    /// - Parameters:
    ///   - hash: The hash of the literal's text.
    ///   - line: The line it starts on; defaults to the current line.
    private mutating func emitLiteral(_ hash: UInt64, line: Int? = nil) {
        tokens.append(CloneToken(hash: keepLiterals ? hash : Self.literalHash, line: line ?? self.line))
    }

    /// Adds a token on the current line.
    ///
    /// - Parameter hash: The hash of its normalized text.
    private mutating func emit(_ hash: UInt64) {
        tokens.append(CloneToken(hash: hash, line: line))
    }

    /// Reports whether a byte can be part of an identifier or number: ASCII letters and digits, `_`, `$`,
    /// and any non-ASCII byte, so Unicode identifiers stay whole.
    ///
    /// - Parameter byte: The byte.
    /// - Returns: Whether it's a word byte.
    private static func isWordByte(_ byte: UInt8) -> Bool {
        let lowercased = byte | Byte.caseBit
        return isDigit(byte) || Byte.lowercaseLetters.contains(lowercased)
            || byte == Byte.underscore || byte == Byte.dollar || byte >= Byte.firstNonASCII
    }

    /// Reports whether a byte is an ASCII digit.
    ///
    /// - Parameter byte: The byte.
    /// - Returns: Whether it's `0`–`9`.
    private static func isDigit(_ byte: UInt8) -> Bool {
        Byte.digits.contains(byte)
    }
}

/// Keywords for every tokenized language, kept verbatim so structure still distinguishes code.
///
/// One shared list keeps the tokenizer language-neutral; a word that's a keyword in another language
/// only matters if it's also used as a name, and then it's kept consistently across copies.
enum CloneKeywords {
    static let all = swift + typeScript + python + go

    private static let swift = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init", "inout",
        "internal", "let", "open", "operator", "private", "protocol", "public", "rethrows", "static", "struct",
        "subscript", "typealias", "var", "break", "case", "continue", "default", "defer", "do", "else",
        "fallthrough", "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while", "as", "catch",
        "false", "is", "nil", "super", "self", "Self", "throw", "throws", "true", "try", "async", "await", "actor",
        "some", "any", "mutating", "override", "final", "lazy", "weak", "unowned", "convenience", "required",
        "indirect", "get", "set", "willSet", "didSet"
    ]
    private static let typeScript = [
        "abstract", "const", "debugger", "delete", "export", "extends", "finally", "from", "function",
        "implements", "instanceof", "interface", "new", "null", "of", "package", "protected", "readonly", "this",
        "type", "typeof", "undefined", "void", "with", "yield", "declare", "namespace", "keyof"
    ]
    private static let python = [
        "False", "None", "True", "and", "assert", "def", "del", "elif", "except", "global", "lambda", "nonlocal",
        "not", "or", "pass", "raise", "match"
    ]
    private static let go = ["chan", "go", "goto", "map", "range", "select"]
}

/// The ASCII bytes the tokenizer looks for.
enum CloneBytes {
    static let newline = UInt8(ascii: "\n"), backslash = UInt8(ascii: "\\"), space = UInt8(ascii: " ")
    static let dot = UInt8(ascii: "."), underscore = UInt8(ascii: "_"), dollar = UInt8(ascii: "$")
    static let digits = UInt8(ascii: "0")...UInt8(ascii: "9")
    static let lowercaseLetters = UInt8(ascii: "a")...UInt8(ascii: "z")
    /// ORing an ASCII letter with this lowercases it.
    static let caseBit = UInt8(ascii: "a") - UInt8(ascii: "A")
    static let firstNonASCII = UInt8(ascii: "\u{7F}") + 1
}
