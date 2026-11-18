import BouncerCore

/// Flags a function that isn't preceded by a doc comment.
///
/// The heuristic analyzer can't reliably determine per-language visibility,
/// so `scope` only takes full effect in `BouncerSwiftAnalyzer`'s AST-based
/// version of this rule - the heuristic version checks every detected
/// function regardless of the `scope` parameter.
public struct MissingDocumentationRule: Rule {
    public static let ruleID = "missing-documentation"
    public let id = MissingDocumentationRule.ruleID
    private let profile: LanguageProfile

    /// Creates the rule for a specific language's function and comment syntax.
    ///
    /// - Parameter profile: The language profile providing the function-start pattern.
    public init(profile: LanguageProfile) {
        self.profile = profile
    }

    /// Flags every function not immediately preceded by a comment line.
    ///
    /// - Parameters:
    ///   - file: The file to scan for functions.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per undocumented function.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, let pattern = profile.functionStartPattern else { return [] }
        return BlockSegmenter.blocks(in: file, startPattern: pattern).compactMap {
            finding(for: $0, in: file, severity: settings.severity)
        }
    }

    /// Builds a finding for one function block if it lacks a preceding comment.
    ///
    /// - Parameters:
    ///   - block: The function's line span.
    ///   - file: The file the function belongs to.
    ///   - severity: The severity to report at.
    /// - Returns: A finding, or `nil` if the function is documented.
    private func finding(for block: LineBlock, in file: SourceFile, severity: Severity) -> Finding? {
        guard !isDocumented(functionStart: block.startLine, in: file) else { return nil }
        let message = "Function has no doc comment above its declaration."
        return Finding(ruleID: id, severity: severity, filePath: file.path, line: block.startLine + 1, message: message)
    }

    /// Checks whether the nearest preceding non-blank line is a comment.
    ///
    /// - Parameters:
    ///   - functionStart: The function declaration's 0-indexed line.
    ///   - file: The file the function belongs to.
    /// - Returns: Whether that line is comment-only.
    private func isDocumented(functionStart: Int, in file: SourceFile) -> Bool {
        var index = functionStart - 1
        while index >= 0, LineClassifier.isBlank(file.lines[index]) { index -= 1 }
        guard index >= 0 else { return false }
        return profile.isCommentOnly(file.lines[index].drop { $0.isWhitespace })
    }
}
