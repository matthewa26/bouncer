import BouncerCore

/// A declaration-naming check: a keyword that introduces a declaration, and the
/// pattern its identifier must match.
public struct NamingRule: Sendable {
    /// A regex capturing the declared identifier in its first capture group,
    /// such as `"func\\s+([A-Za-z_][A-Za-z0-9_]*)"`.
    public let declarationPattern: String
    /// The pattern the captured identifier must match to be considered well-named.
    public let expectedIdentifierPattern: String
    /// A short label for messages, such as `"function"`.
    public let kindLabel: String

    /// Creates a naming rule.
    ///
    /// - Parameters:
    ///   - declarationPattern: A regex capturing the declared identifier.
    ///   - expectedIdentifierPattern: The pattern the identifier must match.
    ///   - kindLabel: A short label for messages.
    public init(declarationPattern: String, expectedIdentifierPattern: String, kindLabel: String) {
        self.declarationPattern = declarationPattern
        self.expectedIdentifierPattern = expectedIdentifierPattern
        self.kindLabel = kindLabel
    }
}

/// The language-specific knowledge the heuristic analyzer needs.
///
/// Adding a new heuristically-analyzed language, or a new pattern rule for an
/// existing one, means adding data here - never a new Swift type. That's what
/// keeps 11 languages sharing one `HeuristicAnalyzer` implementation.
public struct LanguageProfile: Sendable {
    /// The tokens that start a line comment in this language, such as `["//"]` or `["#"]`.
    public let lineCommentPrefixes: [String]
    /// A regex matching a line that opens a function/method body.
    public let functionStartPattern: String?
    /// A regex matching a line that opens a switch-like statement.
    public let switchStartPattern: String?
    /// A regex matching a single branch within a switch-like statement.
    public let switchBranchPattern: String?
    /// A regex matching an import/include/require-style statement.
    public let importLinePattern: String?
    /// Naming conventions checked against this language's declarations.
    public let namingRules: [NamingRule]
    /// Extra pattern rules specific to this language, beyond the 13 shared heuristic rules.
    public let extraPatternRules: [PatternRuleSpec]

    /// Creates a language profile.
    ///
    /// - Parameters:
    ///   - lineCommentPrefixes: The tokens that start a line comment.
    ///   - functionStartPattern: A regex matching a line that opens a function body.
    ///   - switchStartPattern: A regex matching a line that opens a switch-like statement.
    ///   - switchBranchPattern: A regex matching a single branch within a switch statement.
    ///   - importLinePattern: A regex matching an import/include/require statement.
    ///   - namingRules: Naming conventions checked against this language's declarations.
    ///   - extraPatternRules: Extra pattern rules specific to this language.
    public init(
        lineCommentPrefixes: [String],
        functionStartPattern: String? = nil,
        switchStartPattern: String? = nil,
        switchBranchPattern: String? = nil,
        importLinePattern: String? = nil,
        namingRules: [NamingRule] = [],
        extraPatternRules: [PatternRuleSpec] = []
    ) {
        self.lineCommentPrefixes = lineCommentPrefixes
        self.functionStartPattern = functionStartPattern
        self.switchStartPattern = switchStartPattern
        self.switchBranchPattern = switchBranchPattern
        self.importLinePattern = importLinePattern
        self.namingRules = namingRules
        self.extraPatternRules = extraPatternRules
    }

    /// Reports whether a trimmed line is comment-only under this profile.
    ///
    /// - Parameter trimmedLine: A line with leading whitespace already removed.
    /// - Returns: Whether the line starts with one of this language's comment tokens.
    public func isCommentOnly(_ trimmedLine: Substring) -> Bool {
        lineCommentPrefixes.contains { trimmedLine.hasPrefix($0) }
    }
}
