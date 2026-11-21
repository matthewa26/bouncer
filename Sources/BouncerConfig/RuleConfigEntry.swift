import BouncerCore

/// The JSON shape of one rule's entry under `.bouncer`'s `rules` key.
public struct RuleConfigEntry: Codable, Sendable, Equatable {
    public var enabled: Bool?
    public var severity: Severity?
    public var params: [String: RuleParamValue]?

    /// Creates a rule config entry.
    ///
    /// - Parameters:
    ///   - enabled: Whether the rule should run.
    ///   - severity: The severity to report findings at.
    ///   - params: The rule's tunable thresholds.
    public init(enabled: Bool? = nil, severity: Severity? = nil, params: [String: RuleParamValue]? = nil) {
        self.enabled = enabled
        self.severity = severity
        self.params = params
    }

    /// The severity of a rule whose entry doesn't set one, for the rules that don't default to `warning`.
    public static let defaultSeverities: [String: Severity] = ["unpinned-ci-action": .info]

    /// Converts this JSON entry into the `RuleSettings` a `Rule` reads from.
    ///
    /// - Parameter defaultSeverity: The severity to use when the entry doesn't set one.
    /// - Returns: The equivalent, fully-resolved settings.
    public func resolved(defaultSeverity: Severity = .warning) -> RuleSettings {
        let values = (params ?? [:]).mapValues { $0.coreValue }
        return RuleSettings(
            enabled: enabled ?? true, severity: severity ?? defaultSeverity, parameters: RuleParameters(values: values)
        )
    }

    /// Merges another entry's fields over this one's, preferring the other's when both are set.
    ///
    /// - Parameter other: The entry whose fields take precedence.
    /// - Returns: The merged entry.
    public func merging(_ other: RuleConfigEntry) -> RuleConfigEntry {
        RuleConfigEntry(
            enabled: other.enabled ?? enabled,
            severity: other.severity ?? severity,
            params: mergedParams(with: other)
        )
    }

    /// Merges this entry's `params` with another's, preferring the other's on key collision.
    ///
    /// - Parameter other: The entry whose params take precedence.
    /// - Returns: The merged params, or `nil` if neither entry has any.
    private func mergedParams(with other: RuleConfigEntry) -> [String: RuleParamValue]? {
        guard params != nil || other.params != nil else { return nil }
        return (params ?? [:]).merging(other.params ?? [:]) { _, new in new }
    }
}

/// A JSON-decodable rule parameter value, mirroring `RuleParameterValue`.
public enum RuleParamValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case stringList([String])

    /// Converts this JSON value into the `RuleParameterValue` `BouncerCore` understands.
    public var coreValue: RuleParameterValue {
        switch self {
        case .string(let value): return .string(value)
        case .int(let value): return .int(value)
        case .double(let value): return .double(value)
        case .bool(let value): return .bool(value)
        case .stringList(let value): return .stringList(value)
        }
    }

    /// Decodes whichever JSON scalar or string array is present.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: If the value isn't a bool, int, double, string, or string array.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Int.self) { self = .int(value); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        self = .stringList(try container.decode([String].self))
    }

    /// Encodes this value as its underlying JSON scalar or string array.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: If the encoder rejects the value.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .stringList(let value): try container.encode(value)
        }
    }
}
