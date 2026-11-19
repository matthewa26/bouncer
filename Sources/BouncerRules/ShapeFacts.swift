import BouncerCore

/// A closure, lambda, or anonymous function's extent, for the `long-closure` rule.
public struct CollectedClosure: Sendable, Equatable {
    public let startLine: Int
    public let endLine: Int

    /// Creates a collected closure.
    ///
    /// - Parameters:
    ///   - startLine: The 1-indexed line the closure opens on.
    ///   - endLine: The 1-indexed line it closes on.
    public init(startLine: Int, endLine: Int) {
        self.startLine = startLine
        self.endLine = endLine
    }
}

/// A type declaration of any kind (class, struct, enum, actor, protocol, interface), for the
/// `large-type`, `long-identifier`, and `file-name-mismatch` rules.
public struct DeclaredType: Sendable, Equatable {
    public let name: String
    public let startLine: Int
    public let endLine: Int
    /// Whether it's declared at file scope rather than nested in another declaration.
    public let isTopLevel: Bool
    /// `.public` for Swift `public`/`open` or a TS/JS `export`, `.private` for `private`/`fileprivate`.
    public let visibility: DeclarationVisibility

    /// Creates a declared type.
    ///
    /// - Parameters:
    ///   - name: The declared name.
    ///   - startLine: The 1-indexed first line of the declaration.
    ///   - endLine: The 1-indexed last line of the declaration.
    ///   - isTopLevel: Whether it's declared at file scope.
    ///   - visibility: Its access level.
    public init(name: String, startLine: Int, endLine: Int, isTopLevel: Bool, visibility: DeclarationVisibility) {
        self.name = name
        self.startLine = startLine
        self.endLine = endLine
        self.isTopLevel = isTopLevel
        self.visibility = visibility
    }
}

/// The facts behind the size and naming rules that aren't per-function metrics or markers.
public struct ShapeFacts: Sendable {
    public let types: [DeclaredType]
    public let closures: [CollectedClosure]
    /// Every variable, property, and parameter, with its type where it's declared or obvious.
    public let typedNames: [CollectedName]
    /// The names of file-scope declarations other than types that other files can see: functions,
    /// variables, and (Swift) the types extended by top-level `extension`s.
    public let topLevelOthers: [String]

    /// Creates a file's shape facts.
    ///
    /// - Parameters:
    ///   - types: Every type declaration, of any kind.
    ///   - closures: Every closure the `long-closure` rule measures.
    ///   - typedNames: Every variable, property, and parameter, with its type if known.
    ///   - topLevelOthers: The names of visible file-scope declarations that aren't types.
    public init(
        types: [DeclaredType] = [], closures: [CollectedClosure] = [], typedNames: [CollectedName] = [],
        topLevelOthers: [String] = []
    ) {
        self.types = types
        self.closures = closures
        self.typedNames = typedNames
        self.topLevelOthers = topLevelOthers
    }
}
