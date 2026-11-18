import BouncerCore

/// A function or method collected from a file's syntax tree.
public struct CollectedFunction: Sendable {
    /// The name recorded for a function expression nothing binds a name to, such as an inline callback.
    public static let anonymousName = "<anonymous>"

    public let name: String
    public let startLine: Int
    public let endLine: Int
    public let branchCount: Int
    public let hasDocComment: Bool
    public let visibility: DeclarationVisibility
    /// Size and shape measurements, or `nil` where the analyzer doesn't measure this language.
    public let metrics: FunctionMetrics?

    /// Creates a collected function.
    ///
    /// - Parameters:
    ///   - name: The declared name, or `"<anonymous>"`.
    ///   - startLine: The 1-indexed first line of the function.
    ///   - endLine: The 1-indexed last line of the function.
    ///   - branchCount: The number of decision points in its body.
    ///   - hasDocComment: Whether it's documented per its language's convention.
    ///   - visibility: Its access level.
    ///   - metrics: Its size and shape measurements, if measured.
    public init(
        name: String, startLine: Int, endLine: Int, branchCount: Int,
        hasDocComment: Bool, visibility: DeclarationVisibility, metrics: FunctionMetrics? = nil
    ) {
        self.name = name
        self.startLine = startLine
        self.endLine = endLine
        self.branchCount = branchCount
        self.hasDocComment = hasDocComment
        self.visibility = visibility
        self.metrics = metrics
    }
}

/// A function's size and shape measurements, beyond its line span and branch count.
public struct FunctionMetrics: Sendable, Equatable {
    public let parameterCount: Int
    public let returnCount: Int
    public let cognitiveComplexity: Int
    public let maxNestingDepth: Int

    /// Creates a function's measurements.
    ///
    /// - Parameters:
    ///   - parameterCount: The number of declared parameters.
    ///   - returnCount: The number of `return` statements, excluding nested functions and closures.
    ///   - cognitiveComplexity: The SonarSource-style cognitive complexity score.
    ///   - maxNestingDepth: The deepest nesting of control-flow structures.
    public init(parameterCount: Int, returnCount: Int, cognitiveComplexity: Int, maxNestingDepth: Int) {
        self.parameterCount = parameterCount
        self.returnCount = returnCount
        self.cognitiveComplexity = cognitiveComplexity
        self.maxNestingDepth = maxNestingDepth
    }
}

/// A single-location code smell found during a tree walk, reported under its own rule.
public enum MarkerKind: String, Sendable, CaseIterable {
    case forceUnwrap = "force-unwrap"
    case forceTry = "force-try"
    case forceCast = "force-cast"
    case implicitlyUnwrappedOptional = "implicitly-unwrapped-optional"
    case nonNullAssertion = "non-null-assertion"
    case explicitAny = "explicit-any"
    case nestedTernary = "nested-ternary"
    case emptyCatch = "empty-catch"
    case unreachableCode = "unreachable-code"
    case magicNumber = "magic-number"

    /// The rule ID this marker is reported under.
    public var ruleID: String { rawValue }

    /// The finding message for this marker.
    public var message: String { Self.messages[self] ?? rawValue }

    private static let messages: [MarkerKind: String] = [
        .forceUnwrap: "Force unwrap can crash at runtime.",
        .forceTry: "Force try can crash at runtime.",
        .forceCast: "Force cast (as!) can crash at runtime.",
        .implicitlyUnwrappedOptional: "Implicitly unwrapped optional crashes if read while nil; use an optional.",
        .nonNullAssertion: "Non-null assertion (!) bypasses the type checker; narrow the type instead.",
        .explicitAny: "Explicit any disables type checking; use a specific type or unknown.",
        .nestedTernary: "Nested ternary is hard to read; use if/else or a named helper.",
        .emptyCatch: "Empty catch block silently swallows the error.",
        .unreachableCode: "Code after return/throw/break/continue never runs.",
        .magicNumber: "Magic number; name it with a constant."
    ]
}

/// One occurrence of a `MarkerKind` smell.
public struct CollectedMarker: Sendable, Equatable {
    public let kind: MarkerKind
    public let line: Int

    /// Creates a marker.
    ///
    /// - Parameters:
    ///   - kind: Which smell this is.
    ///   - line: The 1-indexed line it occurs on.
    public init(kind: MarkerKind, line: Int) {
        self.kind = kind
        self.line = line
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
    public let markers: [CollectedMarker]

    /// Creates a declaration summary.
    ///
    /// - Parameters:
    ///   - functions: Every function collected from the file.
    ///   - types: Every member-bearing type collected from the file.
    ///   - switches: Every switch/match statement collected from the file.
    ///   - importCount: The file's number of import statements.
    ///   - markers: Every single-location smell found, in source order.
    public init(
        functions: [CollectedFunction], types: [CollectedType], switches: [CollectedSwitch],
        importCount: Int, markers: [CollectedMarker] = []
    ) {
        self.functions = functions
        self.types = types
        self.switches = switches
        self.importCount = importCount
        self.markers = markers
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
