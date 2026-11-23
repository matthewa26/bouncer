import Foundation

/// Any JSON value, for messages whose shape is only known at run time.
///
/// Numbers are held as `Double`, which represents every integer a JSON-RPC id or a tool argument needs; a
/// whole number encodes without a fractional part, so ids and counts round-trip as integers.
public enum JSONValue: Sendable, Equatable, Codable {
    /// `null`.
    case null
    /// `true` or `false`.
    case bool(Bool)
    /// A number, integral or not.
    case number(Double)
    /// A string.
    case string(String)
    /// An ordered list of values.
    case array([JSONValue])
    /// A set of named members.
    case object([String: JSONValue])

    /// The string, or `nil` for any other kind of value.
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// The number as an `Int` when it's a whole number that fits, or `nil` otherwise.
    public var intValue: Int? { // bouncer:disable-line hungarian-notation -- mirrors stringValue and Codable naming
        if case .number(let value) = self { return Int(exactly: value) }
        return nil
    }

    /// The Boolean, or `nil` for any other kind of value.
    public var boolValue: Bool? { // bouncer:disable-line hungarian-notation -- mirrors stringValue and Codable naming
        if case .bool(let value) = self { return value }
        return nil
    }

    /// The elements, or `nil` for any other kind of value.
    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// The members, or `nil` for any other kind of value.
    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// The member named `key`, or `nil` when there's no such member or this isn't an object.
    ///
    /// - Parameter key: The member's name.
    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
}

extension JSONValue {
    /// Decodes any JSON value, trying the scalar kinds before the containers.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` when the input isn't JSON.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let scalar = Self.scalar(in: container) {
            self = scalar
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    /// Reads a `null`, Boolean, number, or string.
    ///
    /// - Parameter container: The container holding the value.
    /// - Returns: The value, or `nil` when it's an array or object.
    private static func scalar(in container: any SingleValueDecodingContainer) -> JSONValue? {
        if container.decodeNil() { return .null }
        if let bool = try? container.decode(Bool.self) { return .bool(bool) }
        if let number = try? container.decode(Double.self) { return .number(number) }
        return (try? container.decode(String.self)).map(JSONValue.string)
    }

    /// Encodes the value, writing a whole number as an integer.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: `EncodingError` for a number JSON can't represent, such as infinity.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        guard let payload else { return try container.encodeNil() }
        try container.encode(payload)
    }

    /// The Swift value this encodes as, with a whole number as an `Int` so it carries no `.0`, or `nil` for `null`.
    private var payload: (any Encodable)? {
        switch self {
        case .null: nil
        case .bool(let value): value
        case .number(let value): Int(exactly: value).map { $0 as any Encodable } ?? value
        case .string(let value): value
        case .array(let value): value
        case .object(let value): value
        }
    }
}

extension JSONValue {
    /// Parses one JSON text.
    ///
    /// - Parameter text: The JSON, which may be any value, not only an object or array.
    /// - Returns: The parsed value.
    /// - Throws: `DecodingError` when `text` isn't valid JSON.
    public static func parse(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    /// Renders the value as compact JSON on a single line, with object members in sorted order.
    ///
    /// - Returns: The JSON text; strings escape their newlines, so the result never contains one.
    /// - Throws: `EncodingError` for a number JSON can't represent, such as infinity.
    public func compactJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    /// Creates a string value from a literal.
    ///
    /// - Parameter value: The string.
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    /// Creates a number value from an integer literal.
    ///
    /// - Parameter value: The integer.
    public init(integerLiteral value: Int) {
        self = .number(Double(value))
    }
}

extension JSONValue: ExpressibleByFloatLiteral {
    /// Creates a number value from a floating-point literal.
    ///
    /// - Parameter value: The number.
    public init(floatLiteral value: Double) {
        self = .number(value)
    }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    /// Creates a Boolean value from a literal.
    ///
    /// - Parameter value: The Boolean.
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension JSONValue: ExpressibleByArrayLiteral {
    /// Creates an array value from a literal.
    ///
    /// - Parameter elements: The elements, in order.
    public init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    /// Creates an object value from a literal; a repeated key keeps its last value.
    ///
    /// - Parameter elements: The members.
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements) { _, last in last })
    }
}
