/// Which dead-code rule an unused declaration is reported under.
public enum DeadCodeKind: String, Sendable, CaseIterable {
    case privateSymbol = "unused-private-symbol"
    case importBinding = "unused-import"
    case parameter = "unused-parameter"

    /// The rule ID this kind is reported under.
    public var ruleID: String { rawValue }

    /// Whether the rule runs only when `.bouncer` configures it, rather than by default.
    public var isOptIn: Bool { self == .parameter }
}

/// A declaration nothing else in its file refers to: a private symbol, an import binding, or a parameter.
public struct UnusedDeclaration: Sendable, Equatable {
    public let kind: DeadCodeKind
    public let name: String
    public let line: Int
    /// What was declared, such as `"Private function"` or `"Unexported class"`; for a parameter, its
    /// function's name.
    public let detail: String

    /// Creates an unused declaration.
    ///
    /// - Parameters:
    ///   - kind: Which dead-code rule reports it.
    ///   - name: The declared identifier.
    ///   - line: The 1-indexed line it's declared on.
    ///   - detail: What was declared, or for a parameter, the function it belongs to.
    public init(kind: DeadCodeKind, name: String, line: Int, detail: String) {
        self.kind = kind
        self.name = name
        self.line = line
        self.detail = detail
    }

    /// The finding message for this declaration.
    public var message: String {
        switch kind {
        case .privateSymbol: return "\(detail) \"\(name)\" is never used in this file."
        case .importBinding: return "Import \"\(name)\" is never used in this file."
        case .parameter: return "Parameter \"\(name)\" of \"\(detail)\" is never used in its body."
        }
    }
}
