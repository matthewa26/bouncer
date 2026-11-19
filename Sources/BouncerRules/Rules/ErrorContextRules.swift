import Foundation
import BouncerCore

/// Flags a Go `if err != nil { return err }` that passes an error up without saying where it came from.
///
/// Opt-in, since a bare return is idiomatic in small helpers. The check is text-based: an `if` testing a name
/// containing `err` against `nil` (with or without an init statement) whose block is a single `return` ending in that
/// same name, on one line or as three lines (`if …{`, `return …, err`, `}`). Test files are skipped.
public struct GoUnwrappedErrorRule: Rule {
    public static let ruleID = "go-unwrapped-error"
    public let id = GoUnwrappedErrorRule.ruleID
    private static let check = TextMatching.regex(#"^\s*if\s+(?:[^;{]*;\s*)?(\w*[eE]rr\w*)\s*!=\s*nil\s*\{\s*(.*)$"#)
    private static let bareReturn = TextMatching.regex(#"^\s*return\s+(?:[^,]+,\s*)*(\w+)\s*(\}?)\s*(?://.*)?$"#)
    private static let closing = TextMatching.regex(#"^\s*\}\s*(?://.*)?$"#)

    /// Creates the rule.
    public init() {}

    /// Flags each error check whose block only returns the error unchanged.
    ///
    /// Runs only when `.bouncer` enables it explicitly.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's settings.
    /// - Returns: One finding per bare return, at its `if` line.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        guard let settings = SourceText.optInSettings(id, context), file.language == .go,
              !TextMatching.isTestPath(file.path) else { return [] }
        let message = "Error returned without context; wrap it, as in fmt.Errorf(\"reading config: %w\", err)."
        return SourceText.flagCodeLines(id, settings, file) { Self.returnsBareError(at: $0, in: file) ? message : nil }
    }

    /// Reports whether the line at `index` checks an error and its block only returns that error.
    ///
    /// - Parameters:
    ///   - index: The candidate `if` line's 0-based index.
    ///   - file: The file it's in.
    /// - Returns: Whether the block is a bare `return …err`.
    private static func returnsBareError(at index: Int, in file: SourceFile) -> Bool {
        guard let match = TextMatching.captures(check, file.lines[index]).first else { return false }
        let name = match[1], rest = match[2]
        if !rest.isEmpty { return returned(rest).map { $0 == (name, true) } ?? false }
        guard index + 2 < file.lines.count, TextMatching.matches(closing, file.lines[index + 2]) else { return false }
        return returned(String(file.lines[index + 1])).map { $0 == (name, false) } ?? false
    }

    /// Reads the last value a `return` statement returns.
    ///
    /// - Parameter text: The statement's text.
    /// - Returns: The returned name and whether the block's `}` follows on the same line, or `nil` if the text
    ///   isn't such a `return`.
    private static func returned(_ text: String) -> (String, Bool)? {
        TextMatching.captures(bareReturn, text).first.map { ($0[1], !$0[2].isEmpty) }
    }
}

/// Flags an error created with a message of only generic words and no detail, such as `new Error("Something went
/// wrong")`, `errors.New("failed")`, `raise ValueError("invalid input")`, or `throw new Exception("Error")`.
///
/// The message must be a plain string literal (no interpolation, format verbs, or concatenation) of at most five
/// words, every one of them generic (`error`, `failed`, `invalid`, `something`, `wrong`, `unknown`, `unexpected`,
/// `occurred`, …), or empty. Messages naming a condition (`"not implemented"`, `"timeout"`, `"unauthorized"`) aren't
/// flagged. Test files are skipped.
public struct GenericErrorMessageRule: Rule {
    public static let ruleID = "generic-error-message"
    public let id = GenericErrorMessageRule.ruleID
    private static let maxWords = 5
    /// The `constructors` capture groups holding the message: a call's argument, or a `throw "…"` statement's.
    private static let (callGroup, statementGroup) = (2, 4)
    private static let constructors = TextMatching.regex(
        #"(?m)(?:\bnew\s+[\w.]*(?:Error|Exception)|\bthrow\s+(?:new\s+)?[\w.:]*(?:Error|Exception|error)|"#
            + #"\braise\s+[\w.]*(?:Error|Exception)|\berrors\.New|\bfmt\.Errorf|\bstd::[a-z_]+_error)"#
            + #"\(\s*(?:message:\s*)?(["'])((?:(?!\1)[^\\])*)\1\s*\)"#
            + #"|\b(?:throw|Write-Error)\s+(["'])((?:(?!\3)[^\\$])*)\3\s*(?:$|[;}])"#
    )
    private static let genericWords: Set = [
        "a", "an", "the", "error", "errors", "err", "failed", "failure", "fail", "fails", "invalid", "something",
        "went", "wrong", "unknown", "unexpected", "occurred", "occured", "has", "have", "had", "oops", "exception",
        "internal", "problem", "bad", "not", "ok", "operation", "could", "cannot", "cant", "can", "unable", "to", "do",
        "it", "this", "that", "is", "was", "there", "happened", "fatal", "issue", "value", "input", "data", "argument",
        "request", "response", "result", "state", "occur", "encountered", "please", "try", "again", "later"
    ]

    /// Creates the rule.
    public init() {}

    /// Flags each error constructed with a generic message.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per generic message.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, !TextMatching.isTestPath(file.path),
              TextMatching.matches(Self.constructors, file.contents) else { return [] }
        return SourceText.flagCodeLines(id, settings, file) { index in
            Self.genericMessage(in: file.lines[index]).map {
                "Error message \"\($0)\" says nothing about what failed; name the operation and the value."
            }
        }
    }

    /// Finds an error constructed with a generic message on a line.
    ///
    /// - Parameter line: The line to check.
    /// - Returns: The generic message, or `nil` if the line has none.
    static func genericMessage(in line: Substring) -> String? {
        TextMatching.captures(constructors, line).lazy.map { $0[1].isEmpty ? $0[statementGroup] : $0[callGroup] }
            .first(where: isGeneric)
    }

    /// Reports whether a message is made only of generic words.
    ///
    /// - Parameter message: The literal's contents.
    /// - Returns: Whether it's empty, or short and every word in it is generic, with no placeholder.
    private static func isGeneric(_ message: String) -> Bool {
        guard !message.contains(where: { "%{$\\".contains($0) }) else { return false }
        let words = message.lowercased().replacingOccurrences(of: "'", with: "")
            .split { !$0.isLetter }.map(String.init)
        return words.count <= maxWords && words.allSatisfy(genericWords.contains)
    }
}
