import Foundation
import BouncerCore

/// Flags a file or stream opened into a local variable that's never closed, returned, or handed off: Go `os.Open`/
/// `os.Create`/`os.OpenFile` with no `Close`, Python `x = open(…)` outside a `with`, Java `new FileInputStream(…)`
/// (and other readers, writers, and sockets) outside try-with-resources, Swift `FileHandle(forReadingAtPath:)` and its
/// siblings, Node `fs.openSync`/`await fs.open`, C `fopen`, and PowerShell `[System.IO.File]::Open…`/`StreamReader`.
///
/// It's text-based. The variable is followed to the end of the block it's declared in (by braces, or by indentation
/// in Python, where module level runs to the end of the file). The handle counts as handled when that stretch calls
/// `x.close()`/`Close()`/`Dispose()`/`closeFile()`, passes `x` to a function whose name contains `close`
/// (`fclose(fp)`, `fs.closeSync(fd)`, `closeQuietly(x)`), mentions `x` itself (not `x.read()`) in a `defer`, `return`,
/// `yield`, or `with`, stores it in a field, struct literal, or `append`, or wraps it in a `new` object that takes
/// ownership.
public struct ResourceLeakRule: Rule {
    public static let ruleID = "resource-leak"
    public let id = ResourceLeakRule.ruleID
    private static let javaTryHeader = TextMatching.regex(#"\btry\s*\("#)

    /// Creates the rule.
    public init() {}

    /// Flags each opened handle that the rest of its block never closes or hands off.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per leaked handle, at the line that opens it.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, let opener = ResourceOpeners.opener(for: file.language),
              TextMatching.matches(opener, file.contents) else { return [] }
        return SourceText.flagCodeLines(id, settings, file) { index in
            guard let name = Self.openedName(at: index, in: file, opener: opener),
                  !Self.isHandled(name, openedAt: index, in: file) else { return nil }
            return "'\(name)' is opened but never closed here; close it with defer, with, using, or try-with-resources."
        }
    }

    /// Reads the variable a line opens a handle into, if it opens one outside try-with-resources.
    ///
    /// - Parameters:
    ///   - index: The line's 0-based index.
    ///   - file: The file it's in.
    ///   - opener: The language's opening pattern.
    /// - Returns: The variable's name, or `nil`.
    private static func openedName(at index: Int, in file: SourceFile, opener: NSRegularExpression?) -> String? {
        let line = SourceText.blankingStrings(file.lines[index])
        guard let name = TextMatching.captures(opener, line).first?[1], !name.isEmpty else { return nil }
        let previous = index > 0 ? file.lines[index - 1] : ""
        let inTryHeader = file.language == .java
            && (TextMatching.matches(javaTryHeader, line) || TextMatching.matches(javaTryHeader, previous))
        return inTryHeader ? nil : name
    }

    /// Reports whether the rest of a handle's block closes it or hands it off.
    ///
    /// - Parameters:
    ///   - name: The handle's variable.
    ///   - index: The 0-based line that opens it.
    ///   - file: The file it's in.
    /// - Returns: Whether some line in the block closes, returns, defers, or stores it.
    private static func isHandled(_ name: String, openedAt index: Int, in file: SourceFile) -> Bool {
        let end = file.language == .python
            ? SourceText.indentedBlockEnd(after: index, in: file)
            : SourceText.enclosingBlockEnd(after: index + 1, in: file)
        let handled = ResourceOpeners.handledPattern(for: name)
        guard index < end else { return false }
        return file.lines[(index + 1)...end].contains { TextMatching.matches(handled, SourceText.code(of: $0)) }
    }
}

/// The per-language patterns `ResourceLeakRule` uses to spot a handle being opened and being handled.
enum ResourceOpeners {
    private static let patterns: [Language: String] = [
        .go: #"^\s*(\w+)\s*,\s*\w+\s*:?=\s*os\.(?:Open|Create|OpenFile)\("#,
        .python: #"^\s*(\w+)\s*=\s*(?:io\.|codecs\.)?open\("#,
        .java: #"\b(\w+)\s*=\s*new\s+(?:FileInputStream|FileOutputStream|FileReader|FileWriter|RandomAccessFile|"#
            + #"BufferedReader|BufferedWriter|PrintWriter|ZipFile|JarFile|Socket|ServerSocket)\("#,
        .swift: #"\b(?:let|var)\s+(\w+)\s*=\s*(?:try\s*[?!]?\s*)?FileHandle\(\s*(?:forReadingAtPath|"#
            + #"forWritingAtPath|forUpdatingAtPath|forReadingFrom|forWritingTo|forUpdating)\s*:"#,
        .typescript: scriptPattern, .javascript: scriptPattern,
        .c: #"\b(\w+)\s*=\s*fopen\("#, .cpp: #"\b(\w+)\s*=\s*(?:std::)?fopen\("#,
        .powershell: #"\$(\w+)\s*=\s*(?:\[System\.IO\.File\]::Open\w*\(|New-Object\s+(?:System\.)?IO\."#
            + #"(?:StreamReader|StreamWriter|FileStream)\b|\[System\.IO\.(?:StreamReader|StreamWriter|FileStream)\]"#
            + #"::new\()"#
    ]
    private static let scriptPattern = #"\b(?:const|let|var)\s+(\w+)\s*=\s*(?:(?:fs\.)?openSync\(|await\s+"#
        + #"(?:fs\.promises\.|fsp\.|fs\.)?open\()"#

    /// Looks up the handle-opening pattern for a language.
    ///
    /// - Parameter language: The file's language.
    /// - Returns: A regex capturing the variable opened into, or `nil` for a language this rule doesn't cover. It
    ///   matches one line, or (as a quick check) a whole file, since `^` matches at each line's start.
    static func opener(for language: Language) -> NSRegularExpression? {
        patterns[language].flatMap { TextMatching.regex("(?m)" + $0) }
    }

    /// Builds the pattern for a line that closes a handle or hands it off.
    ///
    /// - Parameter name: The handle's variable.
    /// - Returns: A regex matching a close, close-like call, `return`, `yield`, `defer`, `with`, field store, or wrap.
    static func handledPattern(for name: String) -> NSRegularExpression? {
        let name = NSRegularExpression.escapedPattern(for: name)
        return TextMatching.regex(
            #"\b\#(name)\s*[?!]?\s*\.\s*(?:Close|close|closeFile|Dispose|dispose)\s*\(|"#
                + #"(?i:close)\w*\(\s*&?\$?\#(name)\b|\bclosing\(\s*\#(name)\b|"#
                + #"\b(?:return|yield|defer|with|using)\b.*\b\#(name)\b(?!\s*[?!]?\s*[.(\[])|"#
                + #"\.\w+\s*=\s*\$?\#(name)\b|\bappend\([^)]*\b\#(name)\b|[:{,]\s*\#(name)\s*[,}]|"#
                + #"\bnew\s+[\w.]+\([^)]*\b\#(name)\b"#
        )
    }
}
