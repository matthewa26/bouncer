import Foundation

/// Matches a relative path against a shell-style glob pattern.
public enum GlobMatcher {
    /// Reports whether a path matches a glob pattern.
    ///
    /// - Parameters:
    ///   - path: A path relative to some root, using `/` separators.
    ///   - pattern: A glob pattern, where `*` matches any run of characters except `/`,
    ///     `**` also matches across `/`, and `?` matches one character.
    /// - Returns: Whether the path matches the pattern.
    public static func matches(path: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: regexPattern(from: pattern)) else { return false }
        return regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
    }

    /// Translates a glob pattern into an anchored regular expression.
    ///
    /// - Parameter pattern: The glob pattern to translate.
    /// - Returns: An equivalent, fully-anchored regex pattern.
    private static func regexPattern(from pattern: String) -> String {
        var result = "^"
        var chars = Array(pattern)
        var index = 0
        while index < chars.count {
            index = appendToken(chars: &chars, at: index, into: &result)
        }
        return result + "$"
    }

    /// Translates one glob token starting at `index` and appends its regex equivalent.
    ///
    /// - Parameters:
    ///   - chars: The pattern's characters.
    ///   - index: The position to translate from.
    ///   - result: The regex built so far, appended to.
    /// - Returns: The index to resume translation from.
    private static func appendToken(chars: inout [Character], at index: Int, into result: inout String) -> Int {
        guard chars[index] == "*", index + 1 < chars.count, chars[index + 1] == "*" else {
            result += regexFragment(for: chars[index])
            return index + 1
        }
        let spansADirectory = index + 2 < chars.count && chars[index + 2] == "/"
        result += spansADirectory ? "(?:.*/)?" : ".*"
        return spansADirectory ? index + 3 : index + 2
    }

    /// Translates a single glob character into its regex fragment.
    ///
    /// - Parameter character: The glob character to translate.
    /// - Returns: The equivalent regex fragment.
    private static func regexFragment(for character: Character) -> String {
        switch character {
        case "*": return "[^/]*"
        case "?": return "[^/]"
        case ".": return "\\."
        default: return String(character)
        }
    }
}
