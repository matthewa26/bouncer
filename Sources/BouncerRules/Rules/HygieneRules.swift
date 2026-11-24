import BouncerCore

/// Flags a non-empty file that doesn't end with a newline.
public struct MissingFinalNewlineRule: Rule {
    public static let ruleID = "missing-final-newline"
    public let id = MissingFinalNewlineRule.ruleID

    /// Creates the rule.
    public init() {}

    /// Flags the file's last line if the file doesn't end with a newline.
    ///
    /// A file ends with one exactly when its last line is empty, which holds for `\r\n` too; Swift treats `"\r\n"`
    /// as one `Character`, so `hasSuffix("\n")` misses it.
    ///
    /// - Parameters:
    ///   - file: The file to check.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: A single finding, or none.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, !file.contents.isEmpty, file.lines.last?.isEmpty == false else { return [] }
        let message = "File doesn't end with a newline."
        let line = file.lines.count
        return [Finding(ruleID: id, severity: settings.severity, filePath: file.path, line: line, message: message)]
    }
}

/// Flags a file that uses Windows (CRLF) line endings.
public struct CrlfLineEndingsRule: Rule {
    public static let ruleID = "crlf-line-endings"
    public let id = CrlfLineEndingsRule.ruleID

    /// Creates the rule.
    public init() {}

    /// Flags the first CRLF line, once per file.
    ///
    /// `SourceFile.lines` already splits on CRLF, so this reads the raw contents instead.
    ///
    /// - Parameters:
    ///   - file: The file to check.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: A single finding, or none.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, let crlf = file.contents.firstIndex(of: "\r\n") else { return [] }
        let line = file.contents[..<crlf].filter { $0 == "\n" || $0 == "\r\n" }.count + 1
        let message = "File uses CRLF line endings; use LF (configure git's core.autocrlf or .gitattributes)."
        return [Finding(ruleID: id, severity: settings.severity, filePath: file.path, line: line, message: message)]
    }
}

/// Flags a file that indents some lines with tabs and others with spaces.
public struct MixedIndentationRule: Rule {
    public static let ruleID = "mixed-indentation"
    public let id = MixedIndentationRule.ruleID

    /// Creates the rule.
    public init() {}

    /// Flags the first line whose indentation style differs from the file's first indented line.
    ///
    /// - Parameters:
    ///   - file: The file to check.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: A single finding, or none.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        let indents = file.lines.enumerated().compactMap { index, line in line.first.map { (index, $0) } }
            .filter { $0.1 == "\t" || $0.1 == " " }
        guard settings.enabled, let style = indents.first?.1,
              let mismatch = indents.first(where: { $0.1 != style }) else { return [] }
        let message = "Indentation mixes tabs and spaces; this line differs from the file's first indented line."
        let line = mismatch.0 + 1
        return [Finding(ruleID: id, severity: settings.severity, filePath: file.path, line: line, message: message)]
    }
}

/// Flags runs of more consecutive blank lines than a configured maximum.
public struct ConsecutiveBlankLinesRule: Rule {
    public static let ruleID = "consecutive-blank-lines"
    public let id = ConsecutiveBlankLinesRule.ruleID

    /// Creates the rule.
    public init() {}

    /// Flags the first line of each run of blank lines longer than `maxBlankLines`.
    ///
    /// - Parameters:
    ///   - file: The file to check.
    ///   - context: Repo-wide state, including this rule's `maxBlankLines` parameter.
    /// - Returns: One finding per over-long run.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled else { return [] }
        let limit = settings.parameters.int("maxBlankLines", default: 2)
        return runStarts(in: file, longerThan: limit).map { start in
            let message = "More than \(limit) consecutive blank lines."
            let line = start + 1
            return Finding(ruleID: id, severity: settings.severity, filePath: file.path, line: line, message: message)
        }
    }

    /// Finds where each run of blank lines longer than `limit` begins.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - limit: The longest allowed run.
    /// - Returns: The 0-indexed first line of each over-long run.
    private func runStarts(in file: SourceFile, longerThan limit: Int) -> [Int] {
        var starts: [Int] = [], run = 0
        for (index, line) in file.lines.enumerated() {
            run = line.allSatisfy(\.isWhitespace) ? run + 1 : 0
            if run == limit + 1 { starts.append(index - limit) }
        }
        return starts
    }
}
