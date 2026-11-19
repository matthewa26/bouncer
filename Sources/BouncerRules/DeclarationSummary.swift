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
    public let booleanParameterCount: Int
    public let returnCount: Int
    public let cognitiveComplexity: Int
    public let maxNestingDepth: Int
    /// Runtime type checks (`instanceof`, `is`, `as?`), a sign the function should use polymorphism.
    public let typeCheckCount: Int

    /// Creates a function's measurements.
    ///
    /// - Parameters:
    ///   - parameterCount: The number of declared parameters.
    ///   - booleanParameterCount: How many of those are boolean flags, by type or by default value.
    ///     Initializers report 0: storing a `Bool` isn't the flag-argument smell of branching on one.
    ///   - returnCount: The number of `return` statements, excluding nested functions and closures.
    ///   - cognitiveComplexity: The SonarSource-style cognitive complexity score.
    ///   - maxNestingDepth: The deepest nesting of control-flow structures.
    ///   - typeCheckCount: The number of runtime type checks.
    public init(
        parameterCount: Int, booleanParameterCount: Int, returnCount: Int,
        cognitiveComplexity: Int, maxNestingDepth: Int, typeCheckCount: Int = 0
    ) {
        self.parameterCount = parameterCount
        self.booleanParameterCount = booleanParameterCount
        self.returnCount = returnCount
        self.cognitiveComplexity = cognitiveComplexity
        self.maxNestingDepth = maxNestingDepth
        self.typeCheckCount = typeCheckCount
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
    case elseAfterReturn = "else-after-return"
    case globalMutableState = "global-mutable-state"
    case longMessageChain = "long-message-chain"
    case testWithoutAssertions = "test-without-assertions"

    /// The rule ID this marker is reported under.
    public var ruleID: String { rawValue }

    /// For markers that carry a measurement, the parameter limiting it, its default, and its unit.
    public var threshold: (parameter: String, defaultLimit: Int, unit: String)? {
        self == .longMessageChain ? ("maxCalls", 5, "calls") : nil
    }

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
        .magicNumber: "Magic number; name it with a constant.",
        .elseAfterReturn: "else after a branch that always exits; drop the else and outdent its body.",
        .globalMutableState: "Mutable global state; pass it in, or make it a constant.",
        .longMessageChain: "Long chain of calls (Law of Demeter); name the intermediate results.",
        .testWithoutAssertions: "Test has no assertions, so it can only fail by crashing."
    ]
}

/// One occurrence of a `MarkerKind` smell.
public struct CollectedMarker: Sendable, Equatable {
    public let kind: MarkerKind
    public let line: Int
    /// The measurement for a thresholded marker, such as a call chain's length; 0 otherwise.
    public let value: Int

    /// Creates a marker.
    ///
    /// - Parameters:
    ///   - kind: Which smell this is.
    ///   - line: The 1-indexed line it occurs on.
    ///   - value: The measurement, for a marker kind with a `threshold`.
    public init(kind: MarkerKind, line: Int, value: Int = 0) {
        self.kind = kind
        self.line = line
        self.value = value
    }
}

/// A variable or parameter declaration, for the naming rules.
public struct CollectedName: Sendable, Equatable {
    public let name: String
    public let line: Int

    /// Creates a collected name.
    ///
    /// - Parameters:
    ///   - name: The declared identifier.
    ///   - line: The 1-indexed line it's declared on.
    public init(name: String, line: Int) {
        self.name = name
        self.line = line
    }
}

/// A plain string literal (no interpolation), for the duplicated-string rule.
public struct CollectedString: Sendable, Equatable {
    public let text: String
    public let line: Int

    /// Creates a collected string literal.
    ///
    /// - Parameters:
    ///   - text: The literal's contents, without quotes.
    ///   - line: The 1-indexed line it appears on.
    public init(text: String, line: Int) {
        self.text = text
        self.line = line
    }
}

/// A class, struct, or other member-bearing type collected from a file's syntax tree.
public struct CollectedType: Sendable {
    public let name: String
    public let memberCount: Int
    public let startLine: Int
    public let endLine: Int
    /// LCOM4: how many unrelated groups its methods split into, or `nil` where it isn't measured.
    public let cohesionGroups: Int?
    /// Its member counts, where measured; `isClass` separates classes from value types for `data-class`.
    public let shape: TypeShape?

    /// Creates a collected type.
    ///
    /// - Parameters:
    ///   - name: The declared name, or `"<anonymous>"`.
    ///   - memberCount: The number of members declared in its body.
    ///   - startLine: The 1-indexed first line of the type.
    ///   - endLine: The 1-indexed last line of the type.
    ///   - cohesionGroups: Its LCOM4 method-group count, if measured.
    ///   - shape: Its method and field counts, if measured.
    public init(
        name: String, memberCount: Int, startLine: Int, endLine: Int,
        cohesionGroups: Int? = nil, shape: TypeShape? = nil
    ) {
        self.name = name
        self.memberCount = memberCount
        self.startLine = startLine
        self.endLine = endLine
        self.cohesionGroups = cohesionGroups
        self.shape = shape
    }
}

/// A type's method and field counts.
public struct TypeShape: Sendable, Equatable {
    public let methodCount: Int
    public let fieldCount: Int
    public let isClass: Bool

    /// Creates a type shape.
    ///
    /// - Parameters:
    ///   - methodCount: Instance and static methods, excluding initializers.
    ///   - fieldCount: Stored or declared properties.
    ///   - isClass: Whether it's a class, as opposed to a struct or other value type.
    public init(methodCount: Int, fieldCount: Int, isClass: Bool) {
        self.methodCount = methodCount
        self.fieldCount = fieldCount
        self.isClass = isClass
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
    public let declaredNames: [CollectedName]
    public let stringLiterals: [CollectedString]
    /// Declarations nothing in the file uses, for the dead-code rules.
    public let unusedDeclarations: [UnusedDeclaration]

    /// Creates a declaration summary.
    ///
    /// - Parameters:
    ///   - functions: Every function collected from the file.
    ///   - types: Every member-bearing type collected from the file.
    ///   - switches: Every switch/match statement collected from the file.
    ///   - importCount: The file's number of import statements.
    ///   - markers: Every single-location smell found, in source order.
    ///   - declaredNames: Every variable and parameter declared, for the naming rules.
    ///   - stringLiterals: Every plain string literal, for the duplicated-string rule.
    ///   - unusedDeclarations: Every private symbol, import, and parameter nothing in the file uses.
    public init(
        functions: [CollectedFunction], types: [CollectedType], switches: [CollectedSwitch], importCount: Int,
        markers: [CollectedMarker] = [], declaredNames: [CollectedName] = [], stringLiterals: [CollectedString] = [],
        unusedDeclarations: [UnusedDeclaration] = []
    ) {
        self.functions = functions
        self.types = types
        self.switches = switches
        self.importCount = importCount
        self.markers = markers
        self.declaredNames = declaredNames
        self.stringLiterals = stringLiterals
        self.unusedDeclarations = unusedDeclarations
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
