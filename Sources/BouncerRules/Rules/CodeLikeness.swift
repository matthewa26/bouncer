import Foundation

/// Scores how much a comment's text reads as source code rather than prose.
///
/// Language-agnostic and text-based: each signal is a shape that's common in code and rare in English (a trailing
/// `;` or `{`, `name = value`, `call(arg)`, a leading `let`/`def`/`#include`), offset by shapes common in prose
/// (mostly plain words, a sentence-ending period, a capitalized opener, a backtick code span). Parsing the comment
/// text with the file's real grammar would be stricter, but most comments are fragments that no grammar accepts.
enum CodeLikeness {
    /// The score at or above which a line reads as code.
    static let codeThreshold = 2.0
    /// The score at or above which a line continues an adjacent stretch of code (a wrapped argument, say).
    static let continuationThreshold = 1.0
    /// The score at or above which a single line reads unambiguously as code, even on its own.
    static let strongThreshold = 4.0

    private static let keywords: Set<String> = [
        "let", "var", "const", "func", "function", "return", "if", "else", "elif", "for", "while", "switch",
        "case", "break", "continue", "import", "def", "class", "struct", "enum", "guard", "defer", "try", "catch",
        "throw", "await", "async", "public", "private", "internal", "fileprivate", "static", "final", "package",
        "fn", "pub", "echo", "export", "yield", "raise", "except", "lambda", "assert", "self", "this", "super",
        "goto", "int", "void", "char", "bool", "float", "double", "unsigned", "namespace", "typedef", "fi",
        "SELECT", "INSERT", "UPDATE", "DELETE", "FROM", "WHERE", "JOIN", "CREATE", "DROP", "ALTER"
    ]

    /// Words that glue English sentences together and almost never appear as bare tokens in code.
    private static let functionWords: Set<String> = [
        "the", "a", "an", "it", "its", "that", "which", "who", "when", "we", "you", "they", "but", "because",
        "means", "is", "of", "to", "be", "are", "was", "were", "should", "would", "will", "can", "does", "than",
        "so", "also", "by", "iff", "has", "have", "been", "there", "here", "into", "onto", "only", "very"
    ]

    /// Compiles one of the scorer's fixed patterns.
    ///
    /// - Parameter pattern: The regex source.
    /// - Returns: The compiled regex, or `nil` if it fails to compile (the signal is then never counted).
    private static func regex(_ pattern: String) -> NSRegularExpression? {
        return try? NSRegularExpression(pattern: pattern)
    }

    /// Tool directives, task markers, and editor markers: comments that look terse but are never code.
    private static let directive = regex(
        #"^(?i:TODO|FIXME|HACK|XXX|NOTE|MARK|BUG|WARNING|SAFETY)\b|^(swiftlint|swiftformat|eslint|prettier|tslint|"#
            + #"jshint|istanbul|c8|pyright|flake8|noqa|NOLINT|clang-format|cspell|shellcheck|webpack\w*|@ts-\w+|"#
            + #"@flow|@jsx|@license|@preserve|#?region|#?endregion|</?editor-fold|swift-tools-version|pragma)\b|"#
            + #"^(type|fmt|isort|go|vim?|ex|pylint|mypy|nolint|sourceMappingURL):|^\+build\b|^-\*-|://|"#
            + #"^(RUN|CHECK|REQUIRES|UNSUPPORTED|XFAIL|expected-\w+)(-[A-Z]+)*:"#
    )
    /// How much each code shape adds to a line's score, from suggestive to near-conclusive.
    private static let (weak, medium, strong, decisive) = (1.0, 1.5, 2.0, 3.0)
    private static let weightedPatterns: [(NSRegularExpression?, Double)] = [
        (regex(#";\s*$|\{\s*$|^[}\])]+[;,)]*\s*$|^\}"#), strong),
        (regex(#"[(\[]\s*$"#), medium),
        (regex(#"[\],]\s*$|[\w\]][!?]?\(.*\)\s*$"#), weak),
        (regex(#"^((export|local|readonly|let|var|const|val|auto|public|private|internal|fileprivate|static|final|"#
            + #"lazy|weak|override)\s+)*"#
            + #"[A-Za-z_$][\w$.\[\]"']*\s*(:=|([+\-*/%|&^]|\?\?)?=(?![=>]))\s*\S"#), strong),
        (regex(#"[A-Za-z_$][\w$]*[!?]?\("#), weak),
        (regex(#"->|=>|&&|\|\||==|!=|::|\$\{?[A-Za-z_]"#), weak),
        (regex(#"^(func|function|def|class|struct|enum|interface|fn)\s+\w+\s*[(<:{]"#), strong),
        (regex(#"^#(include|define|import|if|ifdef|ifndef|endif|pragma)\b|"#
            + #"^from\s+[\w.]+\s+import\s+[\w*(), ]+$"#), decisive),
        (regex(#"^(if|elif|else|for|while|def|class|try|except|with)\b.*:\s*$"#), weak)
    ]
    private static let proseShapes: [(NSRegularExpression?, Double)] = [
        (regex(#"[A-Za-z]\.\s*$"#), -1),
        (regex(#"^[A-Z][a-z']+\s+[a-z']+\b"#), -1),
        (regex(#"`"#), -2)
    ]

    /// Scores one comment line's text.
    ///
    /// - Parameter body: The text after the comment marker.
    /// - Returns: The score; at least `codeThreshold` reads as code. A directive, marker, or URL scores `-.infinity`.
    static func score(_ body: Substring) -> Double {
        let text = body.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !matches(directive, text) else { return -.infinity }
        let shapes = (weightedPatterns + proseShapes).reduce(0.0) { $0 + (matches($1.0, text) ? $1.1 : 0) }
        return shapes + keywordBonus(text) + prosePenalty(text)
    }

    /// Rewards a line whose first token is a language keyword, exactly as code spells it.
    ///
    /// - Parameter text: The trimmed comment text.
    /// - Returns: `1` for a leading keyword, otherwise `0`.
    private static func keywordBonus(_ text: String) -> Double {
        let first = text.prefix { $0.isLetter || $0 == "_" }
        guard keywords.contains(String(first)) else { return 0 }
        let next = text.dropFirst(first.count).first
        return next.map { " (:;".contains($0) } ?? true ? 1 : 0
    }

    /// Penalizes the two strongest signs of prose: mostly plain words, and English function words.
    ///
    /// - Parameter text: The trimmed comment text.
    /// - Returns: `-2` when at least four tokens and 70% of them are plain non-keyword words, another `-2` when
    ///   two or more tokens are function words such as `the`, `it`, or `than`, otherwise `0`.
    private static func prosePenalty(_ text: String) -> Double {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        let functionWordCount = tokens.filter { functionWords.contains($0.lowercased()) }.count
        let wordy = tokens.count >= 4 && Double(tokens.filter { isPlainWord($0) }.count) / Double(tokens.count) >= 0.7
        return (wordy ? -2 : 0) + (functionWordCount >= 2 ? -2 : 0)
    }

    /// Reports whether a token is an ordinary word: letters (and apostrophes), optionally followed by punctuation.
    ///
    /// - Parameter token: One whitespace-separated token.
    /// - Returns: Whether the token is a plain word that isn't a keyword.
    private static func isPlainWord(_ token: Substring) -> Bool {
        let word = token.last.map { ",.:;!?".contains($0) } == true ? token.dropLast() : token
        return !word.isEmpty && word.allSatisfy { $0.isLetter || $0 == "'" } && !keywords.contains(String(word))
    }

    /// Reports whether a regex matches anywhere in a string.
    ///
    /// - Parameters:
    ///   - regex: The compiled pattern, or `nil` if it failed to compile.
    ///   - text: The text to search.
    /// - Returns: Whether the pattern matches.
    private static func matches(_ regex: NSRegularExpression?, _ text: String) -> Bool {
        regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
