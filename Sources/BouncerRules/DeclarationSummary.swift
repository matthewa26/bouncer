import BouncerCore

/// A function or method collected from a file's syntax tree.
public struct CollectedFunction: Sendable {
    public let name: String
    public let startLine: Int
    public let endLine: Int
    public let branchCount: Int
    public let hasDocComment: Bool
    public let visibility: DeclarationVisibility

    /// Creates a collected function.
    ///
    /// - Parameters:
    ///   - name: The declared name, or `"<anonymous>"`.
    ///   - startLine: The 1-indexed first line of the function.
    ///   - endLine: The 1-indexed last line of the function.
    ///   - branchCount: The number of decision points in its body.
    ///   - hasDocComment: Whether it's documented per its language's convention.
    ///   - visibility: Its access level.
    public init(
        name: String, startLine: Int, endLine: Int, branchCount: Int,
        hasDocComment: Bool, visibility: DeclarationVisibility
    ) {
        self.name = name
        self.startLine = startLine
        self.endLine = endLine
        self.branchCount = branchCount
        self.hasDocComment = hasDocComment
        self.visibility = visibility
    }
}

/// A class, struct, or other member-bearing type collected from a file's syntax tree.
public struct CollectedType: Sendable {
    public let name: String
    public let memberCount: Int
    public let startLine: Int
    public let endLine: Int

    /// Creates a collected type.
    ///
    /// - Parameters:
    ///   - name: The declared name, or `"<anonymous>"`.
    ///   - memberCount: The number of members declared in its body.
    ///   - startLine: The 1-indexed first line of the type.
    ///   - endLine: The 1-indexed last line of the type.
    public init(name: String, memberCount: Int, startLine: Int, endLine: Int) {
        self.name = name
        self.memberCount = memberCount
        self.startLine = startLine
        self.endLine = endLine
    }
}

/// A switch or match statement collected from a file's syntax tree.
public struct CollectedSwitch: Sendable {
    public let caseCount: Int
    public let startLine: Int

    /// Creates a collected switch.
    ///
    /// - Parameters:
    ///   - caseCount: The number of branches.
    ///   - startLine: The 1-indexed line the statement starts on.
    public init(caseCount: Int, startLine: Int) {
        self.caseCount = caseCount
        self.startLine = startLine
    }
}

/// Everything the shared AST rules need from one file, whichever parser produced it.
///
/// Both `SwiftSyntaxAnalyzer` and `TreeSitterAnalyzer` build one of these, so
/// each AST rule in `DeclarationFindings` is written once for every language.
public struct DeclarationSummary: Sendable {
    public let functions: [CollectedFunction]
    public let types: [CollectedType]
    public let switches: [CollectedSwitch]
    public let importCount: Int

    /// Creates a declaration summary.
    ///
    /// - Parameters:
    ///   - functions: Every function collected from the file.
    ///   - types: Every member-bearing type collected from the file.
    ///   - switches: Every switch/match statement collected from the file.
    ///   - importCount: The file's number of import statements.
    public init(
        functions: [CollectedFunction], types: [CollectedType], switches: [CollectedSwitch], importCount: Int
    ) {
        self.functions = functions
        self.types = types
        self.switches = switches
        self.importCount = importCount
    }
}

/// The identifier patterns one language's `naming-convention` rule checks against.
public struct NamingPatterns: Sendable {
    public let function: String
    public let type: String?

    /// Creates a language's naming patterns.
    ///
    /// - Parameters:
    ///   - function: The regex every function name must match.
    ///   - type: The regex every type name must match, or `nil` if the language has no classes.
    public init(function: String, type: String?) {
        self.function = function
        self.type = type
    }
}
