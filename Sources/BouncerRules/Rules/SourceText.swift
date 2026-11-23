import Foundation
import BouncerCore

/// Line views the error-handling, concurrency, test, and security text rules share: which lines hold code, a line
/// with its string contents blanked, brace-delimited blocks, and an identifier's words.
enum SourceText {
    /// The most lines a brace block is followed before the scan gives up and treats the block as ending there.
    static let maxBlockLines = 400
    private static let stringLiteral = TextMatching.regex(#""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`"#)
    private static let camelBoundary = TextMatching.regex(#"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])"#)

    /// Marks each line that holds code, rather than being blank, comment-only, or inside a multi-line string.
    ///
    /// For an unrecognized language, whose comment syntax is only guessed, every non-blank line counts as code.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - profile: The language's profile, for its comment syntax.
    /// - Returns: One flag per line.
    static func codeMask(of file: SourceFile, profile: LanguageProfile) -> [Bool] {
        let interior = MultilineStringMask.interiorLines(of: file)
        guard let syntax = CommentSyntax(language: file.language, profile: profile) else {
            return file.lines.indices.map { !interior[$0] && !file.lines[$0].allSatisfy(\.isWhitespace) }
        }
        return CommentScanner.scan(file, syntax: syntax).enumerated().map { index, kind in
            if case .code = kind { return !interior[index] }
            return false
        }
    }

    /// Replaces the contents of every single-line string literal with spaces, keeping the quotes, so code patterns
    /// don't match text inside strings and column positions stay the same.
    ///
    /// - Parameter line: The line to blank.
    /// - Returns: The line with its string contents blanked.
    static func blankingStrings(_ line: some StringProtocol) -> String {
        let text = NSMutableString(string: String(line))
        let matches = stringLiteral?.matches(in: text as String, range: NSRange(location: 0, length: text.length)) ?? []
        for match in matches where match.range.length > 2 {
            let inner = NSRange(location: match.range.location + 1, length: match.range.length - 2)
            text.replaceCharacters(in: inner, with: String(repeating: " ", count: inner.length))
        }
        return text as String
    }

    /// Lists the single-line string literals on a line, quotes included.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: Each literal's text, in order.
    static func stringLiterals(in line: some StringProtocol) -> [String] {
        TextMatching.captures(stringLiteral, line).map { $0[0] }
    }

    /// Reads a line's code: its strings blanked and any trailing `//` comment cut off.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: The code part.
    static func code(of line: some StringProtocol) -> String {
        let blanked = blankingStrings(line)
        return blanked.range(of: "//").map { String(blanked[..<$0.lowerBound]) } ?? blanked
    }

    /// Reads a line's braces, leaving out strings, a trailing `//` comment, and empty `{}` pairs (`interface{}`).
    ///
    /// - Parameter line: The line to read.
    /// - Returns: Its `{` and `}` characters, in order.
    static func braces(of line: some StringProtocol) -> [Character] {
        code(of: line).replacingOccurrences(of: "{}", with: "").filter { $0 == "{" || $0 == "}" }
    }

    /// Finds the last line of the brace block whose `{` is the first one on or after a line.
    ///
    /// - Parameters:
    ///   - start: The 0-based line to start from.
    ///   - file: The file to scan.
    /// - Returns: The 0-based line holding the matching `}`, or the last line scanned if it never closes.
    static func blockEnd(from start: Int, in file: SourceFile) -> Int {
        var depth = 0, opened = false
        return firstLine(from: start, in: file) { char in
            depth += char == "{" ? 1 : -1
            opened = opened || char == "{"
            return opened && depth <= 0
        }
    }

    /// Feeds a file's braces, line by line, to a check until it reports a stop.
    ///
    /// - Parameters:
    ///   - start: The 0-based line to start from.
    ///   - file: The file to scan.
    ///   - stop: Reads each brace in order and reports whether the scan should stop there.
    /// - Returns: The line where it stopped, or the last line scanned (at most `maxBlockLines` on).
    private static func firstLine(from start: Int, in file: SourceFile, until stop: (Character) -> Bool) -> Int {
        let end = min(file.lines.count, start + maxBlockLines)
        for index in start..<max(start, end) where braces(of: file.lines[index]).contains(where: stop) {
            return index
        }
        return max(min(start, file.lines.count - 1), end - 1)
    }

    /// Finds the last line of the block enclosing a line: the first line after it where more braces close than
    /// opened since.
    ///
    /// - Parameters:
    ///   - start: The 0-based line inside the block.
    ///   - file: The file to scan.
    /// - Returns: The 0-based line closing the enclosing block, or the file's last line at top level.
    static func enclosingBlockEnd(after start: Int, in file: SourceFile) -> Int {
        var depth = 0
        return firstLine(from: start, in: file) { char in
            depth += char == "{" ? 1 : -1
            return depth < 0
        }
    }

    /// Finds the last line of the indented block a Python line belongs to: the line before the next non-blank line
    /// indented less than it.
    ///
    /// - Parameters:
    ///   - start: The 0-based line inside the block.
    ///   - file: The file to scan.
    /// - Returns: The 0-based last line of the block.
    static func indentedBlockEnd(after start: Int, in file: SourceFile) -> Int {
        let indent = file.lines[start].prefix(while: \.isWhitespace).count
        let next = file.lines.indices.dropFirst(start + 1).first { index in
            let line = file.lines[index]
            return !line.allSatisfy(\.isWhitespace) && line.prefix(while: \.isWhitespace).count < indent
        }
        return (next ?? file.lines.count) - 1
    }

    /// Splits an identifier into lowercase words at camelCase humps, underscores, hyphens, and digits.
    ///
    /// - Parameter name: An identifier such as `apiKey`, `API_KEY`, or `parseURLString`.
    /// - Returns: Its words, such as `["api", "key"]`.
    static func words(of name: String) -> [String] {
        let range = NSRange(name.startIndex..., in: name)
        let spaced = camelBoundary?.stringByReplacingMatches(in: name, range: range, withTemplate: "_") ?? name
        return spaced.split { $0 == "_" || $0 == "-" || $0.isNumber || $0 == "$" }.map { $0.lowercased() }
    }

    /// Builds a finding for each code line a check flags, skipping blank, comment-only, and multi-line-string lines.
    ///
    /// - Parameters:
    ///   - id: The rule's identifier.
    ///   - settings: The rule's settings, for the severity.
    ///   - file: The file to scan.
    ///   - message: Reads a code line's 0-based index and returns its finding's message, or `nil` to skip it.
    /// - Returns: The findings, in line order.
    static func flagCodeLines(_ id: String, _ settings: RuleSettings, _ file: SourceFile,
                              message: (Int) -> String?) -> [Finding] {
        guard isProgram(file.language) else { return [] }
        let code = codeMask(of: file, profile: LanguageProfiles.profile(for: file.language))
        return file.lines.indices.compactMap { index in
            guard code[index] else { return nil }
            return message(index).map { finding(id, settings, file, index, $0) }
        }
    }

    /// Reports whether a language is a programming language, so its lines are code: every recognized language, and
    /// unrecognized files whose extension names one (Rust, C#, Kotlin, Scala, Dart, Ruby, …) rather than text,
    /// data, or markup such as a test-corpus `.txt`.
    ///
    /// - Parameter language: The file's language.
    /// - Returns: Whether its lines should be read as code.
    static func isProgram(_ language: Language) -> Bool {
        guard case .other(let fileExtension) = language else { return true }
        return otherProgramExtensions.contains(fileExtension.lowercased())
    }

    private static let otherProgramExtensions: Set = [
        "rs", "cs", "kt", "kts", "scala", "dart", "groovy", "gradle", "m", "mm", "rb", "lua", "pl", "pm", "r",
        "ex", "exs", "erl", "hs", "clj", "fs", "fsx", "vb", "zig", "nim", "cr", "jl", "ml"
    ]

    /// Builds a finding for a line.
    ///
    /// - Parameters:
    ///   - id: The rule's identifier.
    ///   - settings: The rule's settings, for the severity.
    ///   - file: The file the line is in.
    ///   - index: The line's 0-based index.
    ///   - message: The finding's message.
    /// - Returns: The finding, at the line's 1-based number.
    static func finding(_ id: String, _ settings: RuleSettings, _ file: SourceFile, _ index: Int, _ message: String)
        -> Finding {
        Finding(ruleID: id, severity: settings.severity, filePath: file.path, line: index + 1, message: message)
    }

    /// Reads an opt-in rule's settings: present in the configuration and enabled.
    ///
    /// - Parameters:
    ///   - id: The rule's identifier.
    ///   - context: Repo-wide state, including the configured rules.
    /// - Returns: The settings, or `nil` if the configuration doesn't enable the rule.
    static func optInSettings(_ id: String, _ context: AnalysisContext) -> RuleSettings? {
        guard let settings = context.ruleSettings[id], settings.enabled else { return nil }
        return settings
    }
}
