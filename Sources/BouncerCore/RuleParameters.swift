/// A single value inside a rule's parameter bag.
///
/// Mirrors the shape a JSON value can take, since rule parameters come from
/// the `.bouncer` config file but `BouncerCore` doesn't depend on the config
/// module that parses it.
public enum RuleParameterValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case stringList([String])
}

/// The configurable parameters for one rule, such as a length threshold.
///
/// Built by `BouncerConfig` from `.bouncer` and read by the `Rule`
/// implementations in `BouncerRules`, keeping both sides decoupled from each
/// other's concrete types.
public struct RuleParameters: Sendable, Equatable {
    private let values: [String: RuleParameterValue]

    /// An empty parameter bag, used when a rule has no config entry.
    public static let empty = RuleParameters(values: [:])

    /// Creates a parameter bag from a name-to-value map.
    ///
    /// - Parameter values: The parameter names and their values.
    public init(values: [String: RuleParameterValue]) {
        self.values = values
    }

    /// Reads an integer parameter, falling back to a default if absent.
    ///
    /// - Parameters:
    ///   - name: The parameter name.
    ///   - fallback: The value to use if the parameter isn't set.
    /// - Returns: The configured value, or `fallback`.
    public func int(_ name: String, default fallback: Int) -> Int {
        if case .int(let value)? = values[name] { return value }
        return fallback
    }

    /// Reads a string parameter, falling back to a default if absent.
    ///
    /// - Parameters:
    ///   - name: The parameter name.
    ///   - fallback: The value to use if the parameter isn't set.
    /// - Returns: The configured value, or `fallback`.
    public func string(_ name: String, default fallback: String) -> String {
        if case .string(let value)? = values[name] { return value }
        return fallback
    }

    /// Reads a string-list parameter, falling back to a default if absent.
    ///
    /// - Parameters:
    ///   - name: The parameter name.
    ///   - fallback: The value to use if the parameter isn't set.
    /// - Returns: The configured value, or `fallback`.
    public func stringList(_ name: String, default fallback: [String]) -> [String] {
        if case .stringList(let value)? = values[name] { return value }
        return fallback
    }
}
