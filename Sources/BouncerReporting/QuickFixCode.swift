import Foundation
import BouncerCore

/// A regular expression a fixer matches against one line, reporting matches as character offsets.
struct TextPattern: Sendable {
    /// The compiled expression, or `nil` if the built-in pattern doesn't compile.
    private let regex: NSRegularExpression?

    /// Compiles a pattern.
    ///
    /// - Parameter pattern: The regular expression.
    init(_ pattern: String) {
        regex = try? NSRegularExpression(pattern: pattern)
    }

    /// Checks whether the pattern matches anywhere in a text.
    ///
    /// - Parameter text: The text.
    /// - Returns: Whether there's a match.
    func matches(_ text: String) -> Bool {
        !ranges(in: text).isEmpty
    }

    /// Finds every match in a text.
    ///
    /// - Parameter text: The text.
    /// - Returns: Each match's range, as character offsets.
    func ranges(in text: String) -> [Range<Int>] {
        matches(in: text).compactMap { Range($0.range, in: text) }.map { range in
            text.distance(from: text.startIndex, to: range.lowerBound)
                ..< text.distance(from: text.startIndex, to: range.upperBound)
        }
    }

    /// Reads the capture groups of the first match.
    ///
    /// - Parameter text: The text.
    /// - Returns: The whole match then each group (empty for a group that didn't take part), or `nil` for no match.
    func captures(in text: String) -> [String]? {
        guard let match = matches(in: text).first else { return nil }
        return (0..<match.numberOfRanges).map { group in
            Range(match.range(at: group), in: text).map { String(text[$0]) } ?? ""
        }
    }

    /// Runs the expression over a whole text.
    ///
    /// - Parameter text: The text.
    /// - Returns: The matches, in order.
    private func matches(in text: String) -> [NSTextCheckingResult] {
        regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
    }
}

/// One line of code with its string contents and trailing comment blanked out, so a fixer only matches code.
///
/// Masking keeps each character's position: string contents and comments become spaces, while the quotes
/// themselves stay, so a match in the masked text is at the same offset in the original.
struct MaskedLine: Sendable {
    /// The line's characters, as written.
    let original: [Character]
    /// The masked line.
    let masked: String

    /// Masks a line.
    ///
    /// - Parameters:
    ///   - text: The line.
    ///   - language: Its language, which decides the quotes and comment markers.
    /// - Returns: `nil` when a string is still open at the end of the line, as in a multi-line string.
    init?(_ text: String, language: Language) {
        var masker = Masker(language: language)
        guard let masked = masker.mask(Array(text)) else { return nil }
        original = Array(text)
        self.masked = String(masked)
    }

    /// Finds a pattern's matches in the masked line.
    ///
    /// - Parameter pattern: The pattern.
    /// - Returns: Each match's character range.
    func ranges(of pattern: TextPattern) -> [Range<Int>] {
        pattern.ranges(in: masked)
    }

    /// The line with one range of characters replaced.
    ///
    /// - Parameters:
    ///   - range: The characters to replace.
    ///   - replacement: Their replacement.
    /// - Returns: The new line.
    func replacing(_ range: Range<Int>, with replacement: String) -> String {
        String(original[..<range.lowerBound]) + replacement + String(original[range.upperBound...])
    }

    /// The original text of a range of characters.
    ///
    /// - Parameter range: The range.
    /// - Returns: Its characters, as written.
    func text(_ range: Range<Int>) -> String {
        String(original[range])
    }

    /// The masked text of a range of characters.
    ///
    /// - Parameter range: The range.
    /// - Returns: Its masked characters.
    func code(_ range: Range<Int>) -> String {
        String(Array(masked)[range])
    }

    /// Checks whether masked code has a comma outside any brackets, as between two declarators or arguments.
    ///
    /// - Parameter code: Masked code.
    /// - Returns: Whether such a comma is there.
    static func hasTopLevelComma(_ code: String) -> Bool {
        var depth = 0
        for character in code {
            if "([{".contains(character) { depth += 1 }
            if ")]}".contains(character) { depth -= 1 }
            if character == ",", depth == 0 { return true }
        }
        return false
    }

    /// Finds the bracket that closes the one at an offset, skipping brackets inside strings.
    ///
    /// - Parameter open: The offset of an opening `(`, `[`, or `{`.
    /// - Returns: The offset of its closing bracket, or `nil` when the line doesn't close it.
    func closingBracket(of open: Int) -> Int? {
        var depth = 0
        for (offset, character) in Array(masked).enumerated().dropFirst(open) {
            if "([{".contains(character) { depth += 1 }
            if ")]}".contains(character) { depth -= 1 }
            if depth == 0 { return offset }
        }
        return nil
    }
}

/// Blanks the strings and trailing comment of one line, tracking which quote is open.
private struct Masker {
    /// The characters that open and close a string.
    let quotes: Set<Character>
    /// The markers that start a comment running to the end of the line.
    let commentMarkers: [String]
    /// The quote of the string being read, or `nil` outside one.
    private var quote: Character?
    /// Whether the previous character was a backslash inside a string.
    private var isEscaped = false

    /// Sets up the quotes and comment markers for a language.
    ///
    /// - Parameter language: The line's language.
    init(language: Language) {
        switch language {
        case .swift, .rust: quotes = ["\""]
        case .python: quotes = ["\"", "'"]
        default: quotes = ["\"", "'", "`"]
        }
        commentMarkers = Self.commentMarkers(for: language)
    }

    /// The markers that start a line comment in a language.
    ///
    /// - Parameter language: The language.
    /// - Returns: `#` for Python and the shells, both `//` and `#` for PHP, and `//` otherwise.
    private static func commentMarkers(for language: Language) -> [String] {
        switch language {
        case .python, .bash, .zsh, .powershell: ["#"]
        case .php: ["//", "#"]
        default: ["//"]
        }
    }

    /// Masks a line's characters.
    ///
    /// - Parameter characters: The line.
    /// - Returns: The masked characters, or `nil` when a string is left open.
    mutating func mask(_ characters: [Character]) -> [Character]? {
        var output: [Character] = []
        for (offset, character) in characters.enumerated() {
            if quote == nil, startsComment(characters, at: offset) {
                return output + Array(repeating: " ", count: characters.count - offset)
            }
            output.append(step(character))
        }
        return quote == nil ? output : nil
    }

    /// Masks one character, opening or closing a string as it goes.
    ///
    /// - Parameter character: The character.
    /// - Returns: The character, or a space for one inside a string.
    private mutating func step(_ character: Character) -> Character {
        guard let open = quote else {
            if quotes.contains(character) { quote = character }
            return character
        }
        if isEscaped || character == "\\" { isEscaped.toggle(); return " " }
        if character == open { quote = nil; return character }
        return " "
    }

    /// Checks whether a comment marker starts at an offset.
    ///
    /// - Parameters:
    ///   - characters: The line.
    ///   - offset: The offset.
    /// - Returns: Whether one of the language's comment markers starts there.
    private func startsComment(_ characters: [Character], at offset: Int) -> Bool {
        commentMarkers.contains { marker in characters[offset...].starts(with: Array(marker)) }
    }
}
