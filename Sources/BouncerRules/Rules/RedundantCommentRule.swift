import Foundation
import BouncerCore

/// Flags a one-line comment that only restates the line of code below it, such as `// increment counter`
/// above `counter += 1`.
///
/// Opt-in, and deliberately narrow: the comment must be a lone, non-doc line comment of plain words, have at least
/// two content words once stop words are dropped, and every one of them (after light stemming) must appear among the
/// next line's identifiers, keywords, or the verbs its operators imply.
public struct RedundantCommentRule: Rule {
    public static let ruleID = "redundant-comment"
    public let id = RedundantCommentRule.ruleID
    private let profile: LanguageProfile

    /// Creates the rule for one language.
    ///
    /// - Parameter profile: The language's profile, for its comment syntax.
    public init(profile: LanguageProfile) {
        self.profile = profile
    }

    /// Flags each lone comment whose words all restate the code line below it.
    ///
    /// Runs only when `.bouncer` enables it explicitly.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's settings.
    /// - Returns: One finding per redundant comment.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        guard let settings = context.ruleSettings[id], settings.enabled,
              let syntax = CommentSyntax(language: file.language, profile: profile) else { return [] }
        let lines = CommentScanner.scan(file, syntax: syntax)
        return lines.indices.compactMap { index in
            guard isRedundant(at: index, in: lines, file: file) else { return nil }
            let message = "Comment restates the next line; delete it, or say why instead of what."
            let line = index + 1
            return Finding(ruleID: id, severity: settings.severity, filePath: file.path, line: line, message: message)
        }
    }

    /// Reports whether the line at `index` is a lone comment that restates the code line after it.
    ///
    /// - Parameters:
    ///   - index: The candidate comment's 0-based line index.
    ///   - lines: The file's scanned lines.
    ///   - file: The file, for the code line's text.
    /// - Returns: Whether the comment is redundant.
    private func isRedundant(at index: Int, in lines: [ScannedLine], file: SourceFile) -> Bool {
        guard case .comment(let comment) = lines[index], !comment.isDoc, !comment.isBlock,
              index + 1 < lines.count, case .code = lines[index + 1] else { return false }
        if index > 0, case .comment = lines[index - 1] { return false }
        guard let words = RestatementWords.commentWords(comment.body), words.count >= 2,
              Self.isSingleLineStatement(at: index + 1, in: file) else { return false }
        return words.isSubset(of: RestatementWords.codeWords(file.lines[index + 1]))
    }

    /// Reports whether a code line is a whole statement on its own, so a comment above it can only describe it.
    ///
    /// A line that ends by opening a block, argument list, or expression continuation, or that the next line
    /// continues (more indented, or a leading `.` chain), heads a larger construct the comment may be labeling.
    ///
    /// - Parameters:
    ///   - index: The code line's 0-based index.
    ///   - file: The file it's in.
    /// - Returns: Whether the line stands alone.
    private static func isSingleLineStatement(at index: Int, in file: SourceFile) -> Bool {
        let line = file.lines[index].trimmingCharacters(in: .whitespaces)
        guard let last = line.last, !"{([,=>:\\+-*/&|.?".contains(last), !line.hasSuffix(" in") else { return false }
        guard index + 1 < file.lines.count else { return true }
        let next = file.lines[index + 1]
        let nextTrimmed = next.drop { $0.isWhitespace }
        let isMoreIndented = !nextTrimmed.isEmpty && next.count - nextTrimmed.count > indent(of: file.lines[index])
        return !isMoreIndented && !nextTrimmed.hasPrefix(".")
    }

    /// Measures a line's leading whitespace.
    ///
    /// - Parameter line: The line to measure.
    /// - Returns: The number of leading whitespace characters.
    private static func indent(of line: Substring) -> Int {
        line.prefix { $0.isWhitespace }.count
    }
}

/// The word sets `RedundantCommentRule` compares: a comment's content words and the words a code line spells.
enum RestatementWords {
    private static let stopWords: Set<String> = [
        "the", "a", "an", "to", "of", "and", "or", "in", "on", "for", "with", "by", "from", "at", "this", "that",
        "it", "its", "is", "are", "be", "as", "into", "our", "we", "new", "now", "then", "here", "just"
    ]
    /// The suffixes `stem` strips, each only when at least `minStemLength` letters remain so short words stay intact.
    private static let suffixes = ["ing", "ed", "s"]
    private static let minStemLength = 3
    private static let identifier = try? NSRegularExpression(pattern: #"[A-Za-z_][A-Za-z0-9_]*"#)
    private static let camelBoundary = try? NSRegularExpression(pattern: #"([a-z0-9])([A-Z])|([A-Z])([A-Z][a-z])"#)
    private static let impliedVerbs: [(NSRegularExpression?, [String])] = [
        (try? NSRegularExpression(pattern: #"(^|[^=!<>+\-*/%&|^:?])=($|[^=>])"#),
         ["set", "assign"]),
        (try? NSRegularExpression(pattern: #"\+=|\+\+"#), ["increment", "increase", "add"]),
        (try? NSRegularExpression(pattern: #"-=|--"#), ["decrement", "decrease", "subtract"]),
        (try? NSRegularExpression(pattern: #"^\s*(let|var|const|val)\b"#),
         ["declare", "define", "create", "make", "initialize", "init"]),
        (try? NSRegularExpression(pattern: #"^\s*(if|guard)\b"#), ["check"])
    ]

    /// Extracts a comment's content words, if it's plain prose.
    ///
    /// - Parameter body: The text after the comment marker.
    /// - Returns: The stemmed, lowercased words minus stop words, or `nil` if the comment holds anything but words
    ///   (digits, symbols, code), which this rule leaves alone.
    static func commentWords(_ body: Substring) -> Set<String>? {
        var text = body.trimmingCharacters(in: .whitespaces)
        if text.last.map({ ".!".contains($0) }) == true { text.removeLast() }
        let tokens = text.split(separator: " ")
        guard !tokens.isEmpty, tokens.allSatisfy({ $0.allSatisfy(\.isLetter) }) else { return nil }
        return Set(tokens.map { stem($0.lowercased()) }.filter { !stopWords.contains($0) })
    }

    /// Collects the words a code line spells: its identifiers and keywords, split on camelCase and snake_case,
    /// plus the verbs its operators imply.
    ///
    /// - Parameter line: The code line.
    /// - Returns: The stemmed, lowercased words.
    static func codeWords(_ line: Substring) -> Set<String> {
        let text = String(line)
        let range = NSRange(text.startIndex..., in: text)
        let names = identifier?.matches(in: text, range: range).compactMap { Range($0.range, in: text) } ?? []
        let words = names.flatMap { splitIdentifier(String(text[$0])) }
        let verbs = impliedVerbs.filter { $0.0?.firstMatch(in: text, range: range) != nil }.flatMap(\.1)
        return Set((words + verbs).map(stem))
    }

    /// Splits an identifier into its lowercased words, keeping the whole identifier too.
    ///
    /// - Parameter name: An identifier such as `userName` or `max_count`.
    /// - Returns: Its words, such as `["username", "user", "name"]`.
    private static func splitIdentifier(_ name: String) -> [String] {
        let range = NSRange(name.startIndex..., in: name)
        let spaced = camelBoundary?.stringByReplacingMatches(in: name, range: range, withTemplate: "$1$3_$2$4") ?? name
        let parts = spaced.split(separator: "_").map { $0.lowercased() }
        return [name.lowercased()] + parts
    }

    /// Reduces a word to a rough stem, so `increments`, `incremented`, and `incrementing` all match `increment`.
    ///
    /// - Parameter word: A lowercased word.
    /// - Returns: The word without a trailing `-ing`, `-ed`, or `-s`.
    static func stem(_ word: String) -> String {
        guard !word.hasSuffix("ss"),
              let suffix = suffixes.first(where: { word.count >= $0.count + minStemLength && word.hasSuffix($0) })
        else { return word }
        return String(word.dropLast(suffix.count))
    }
}
