/// The doc-comment conventions the doc-completeness rules can read.
public enum DocStyle: Sendable, Equatable {
    /// Swift `///` or `/** */` with `- Parameter(s):`, `- Returns:`, and `- Throws:` callouts.
    case swift
    /// JSDoc `/** */` with `@param`, `@returns`, and `@throws` tags.
    case jsdoc
    /// A Python docstring in Google (`Args:`), NumPy (`Parameters` and dashes), or reST (`:param x:`) style.
    case python
}

/// One parameter in a function's signature, as the doc-completeness rules match it against its doc.
public struct SignatureParameter: Sendable, Equatable {
    /// The name the body uses, such as `value` in Swift's `with value: Int`.
    public let name: String
    /// Other names a doc may use for it, such as Swift's argument label `with`.
    public let aliases: [String]
    /// Whether it's a Python `*args`/`**kwargs`, which docs often describe elsewhere, so it's never missing.
    public let isVariadic: Bool

    /// Creates a signature parameter.
    ///
    /// - Parameters:
    ///   - name: The name the body uses.
    ///   - aliases: Other names a doc may use for it.
    ///   - isVariadic: Whether a missing entry for it is excused.
    public init(name: String, aliases: [String] = [], isVariadic: Bool = false) {
        self.name = name
        self.aliases = aliases
        self.isVariadic = isVariadic
    }

    /// Every name a doc may use for this parameter.
    public var names: Set<String> { Set([name] + aliases) }
}

/// A documented function's doc comment and the parts of its signature a doc should describe.
public struct DocumentationFacts: Sendable, Equatable {
    public let style: DocStyle
    /// The doc comment's raw text, comment markers and all.
    public let text: String
    public let parameters: [SignatureParameter]
    /// Whether some parameter has no name to match, such as a destructured `{ a, b }`, or gathers named
    /// arguments, such as `**kwargs`, so a documented name missing from the signature may well describe it.
    public let hasUnnamedParameters: Bool
    /// Whether it returns a value: a non-`Void` return type, or a `return` with a value in its own body.
    public let returnsValue: Bool
    /// Whether it throws: Swift `throws`, or a `throw`/`raise` in its own body outside any `try`.
    public let throwsError: Bool

    /// Creates a function's documentation facts.
    ///
    /// - Parameters:
    ///   - style: The doc convention to parse `text` with.
    ///   - text: The doc comment's raw text.
    ///   - parameters: The signature's named parameters.
    ///   - hasUnnamedParameters: Whether some parameter has no name to match.
    ///   - returnsValue: Whether it returns a value.
    ///   - throwsError: Whether it throws.
    public init(
        style: DocStyle, text: String, parameters: [SignatureParameter], hasUnnamedParameters: Bool = false,
        returnsValue: Bool, throwsError: Bool
    ) {
        self.style = style
        self.text = text
        self.parameters = parameters
        self.hasUnnamedParameters = hasUnnamedParameters
        self.returnsValue = returnsValue
        self.throwsError = throwsError
    }
}
