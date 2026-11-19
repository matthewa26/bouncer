import Foundation
import BouncerCore

/// One piece of another object's state, for `tell-dont-ask`: the object's source text, such as
/// `account` or `self.account`, and the state's name from `DesignVocabulary.stateName(of:)`.
public struct ObjectState: Hashable, Sendable {
    public let object: String
    public let state: String

    /// Creates an object's state.
    ///
    /// - Parameters:
    ///   - object: The object's source text.
    ///   - state: The state's normalized name.
    public init(object: String, state: String) {
        self.object = object
        self.state = state
    }
}

/// The names the design-smell collectors and rules treat specially: mutating calls, getters, library
/// accessors that aren't another object's domain data, and each language's built-in types.
public enum DesignVocabulary {
    /// Calls that change their receiver, so `self.items.append(x)` mutates the field `items`.
    public static let mutatorNames: Set<String> = [
        "append", "insert", "remove", "removeAll", "removeFirst", "removeLast", "removeValue", "popLast",
        "popFirst", "push", "pop", "shift", "unshift", "splice", "add", "delete", "clear", "set", "update",
        "merge", "formUnion", "formIntersection", "subtract", "sort", "reverse", "shuffle", "extend", "discard",
        "setdefault", "toggle", "appendContentsOf", "append_contents", "updateValue", "fill"
    ]

    /// Members that are a library value's own bookkeeping rather than another object's domain data.
    private static let libraryAccessors: Set<String> = [
        "count", "isEmpty", "length", "size", "first", "last", "description", "debugDescription", "startIndex",
        "endIndex", "indices", "keys", "values", "rawValue", "hashValue", "pointee", "self", "Type", "lowercased",
        "uppercased", "utf8", "utf16", "unicodeScalars", "isNaN", "magnitude", "min", "max", "constructor",
        "prototype", "message", "stack", "__class__", "__dict__", "__name__", "real", "imag"
    ]

    /// Reports whether a member access reads another object's data: a property that isn't a library
    /// accessor, or a call to a `getX()`/`get_x()` getter.
    ///
    /// - Parameters:
    ///   - member: The member's name.
    ///   - isCalled: Whether the access is called.
    /// - Returns: Whether it counts toward ATFD and feature envy.
    public static func isForeignData(_ member: String, isCalled: Bool) -> Bool {
        guard let first = member.first, first.isLetter || first == "_", !isLibraryAccessor(member) else {
            return false
        }
        return !isCalled || isGetter(member)
    }

    /// Reports whether a member is a library value's bookkeeping, such as `count` or `length`, rather
    /// than domain state.
    ///
    /// - Parameter member: The member's name.
    /// - Returns: Whether it's a library accessor.
    public static func isLibraryAccessor(_ member: String) -> Bool {
        libraryAccessors.contains(member)
    }

    /// Reports whether a method name reads as a getter, such as `getTotal` or `get_total`.
    ///
    /// - Parameter name: The method's name.
    /// - Returns: Whether it starts with `get` followed by an uppercase letter or `_`.
    static func isGetter(_ name: String) -> Bool {
        hasVerbPrefix("get", name)
    }

    /// Reports whether a method name reads as a setter, such as `setTotal` or `set_total`.
    ///
    /// - Parameter name: The method's name.
    /// - Returns: Whether it starts with `set` followed by an uppercase letter or `_`.
    public static func isSetter(_ name: String) -> Bool {
        hasVerbPrefix("set", name)
    }

    /// Reduces a member name to the state it reads or writes, so `balance`, `getBalance`, `setBalance`,
    /// `get_balance`, and `isBalance` all match.
    ///
    /// - Parameter member: The member's name.
    /// - Returns: The name without a leading `get`/`set`/`is`/`has` verb or underscores, lowercased.
    public static func stateName(of member: String) -> String {
        let verb = ["get", "set", "is", "has"].first { hasVerbPrefix($0, member) }
        return member.dropFirst(verb?.count ?? 0).filter { $0 != "_" }.lowercased()
    }

    /// Reports whether a name starts with a verb as its own camelCase or snake_case word.
    ///
    /// - Parameters:
    ///   - verb: The lowercase verb, such as `get`.
    ///   - name: The name.
    /// - Returns: Whether the name is the verb followed by an uppercase letter or `_`.
    private static func hasVerbPrefix(_ verb: String, _ name: String) -> Bool {
        guard name.hasPrefix(verb), let next = name.dropFirst(verb.count).first else { return false }
        return next.isUppercase || next == "_"
    }

    /// Reports whether a type name is one of a language's built-in or standard-library types, which
    /// don't count toward CBO.
    ///
    /// - Parameters:
    ///   - name: The type's name, such as `String` or `Promise`.
    ///   - language: The file's language.
    /// - Returns: Whether it's a built-in type.
    public static func isLibraryType(_ name: String, in language: Language) -> Bool {
        switch language {
        case .swift: return swiftTypes.contains(name)
        case .python: return pythonTypes.contains(name) || name.hasSuffix("Error") || name.hasSuffix("Exception")
        case .typescript, .javascript: return javascriptTypes.contains(name) || name.hasSuffix("Error")
        default: return false
        }
    }

    private static let swiftTypes: Set<String> = [
        "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Double", "Float",
        "Float80", "CGFloat", "Bool", "String", "Substring", "Character", "Array", "Dictionary", "Set", "Optional",
        "Result", "Error", "Never", "Void", "Any", "AnyObject", "AnyHashable", "Self", "Range", "ClosedRange",
        "Sequence", "Collection", "IteratorProtocol", "Equatable", "Hashable", "Comparable", "Codable",
        "Encodable", "Decodable", "Encoder", "Decoder", "CodingKey", "Hasher", "Sendable", "Identifiable",
        "CustomStringConvertible", "CustomDebugStringConvertible", "Task", "MainActor", "Data", "Date", "URL",
        "UUID", "TimeInterval", "DispatchQueue", "NSLock", "NSObject", "ObservableObject", "Published",
        "Error", "LocalizedError", "StaticString", "Unicode", "ArraySlice", "Slice", "KeyPath", "Mirror",
        "ContiguousArray", "OptionSet", "RawRepresentable", "CaseIterable", "ExpressibleByStringLiteral",
        "Character", "CharacterSet", "JSONEncoder", "JSONDecoder", "FileManager", "ProcessInfo", "NSRange",
        "NSRegularExpression", "Locale", "Calendar", "DateFormatter", "Bundle", "NotificationCenter", "XCTest",
        "XCTestCase", "AsyncStream", "AsyncSequence", "Duration", "ContinuousClock", "UnsafeMutablePointer",
        "UnsafePointer", "UnsafeRawPointer", "UnsafeMutableRawPointer", "UnsafeBufferPointer", "OpaquePointer"
    ]

    private static let pythonTypes: Set<String> = [
        "int", "str", "float", "bool", "bytes", "bytearray", "list", "dict", "set", "frozenset", "tuple", "object",
        "type", "None", "complex", "range", "slice", "memoryview", "Any", "Optional", "Union", "List", "Dict",
        "Set", "FrozenSet", "Tuple", "Type", "Callable", "Iterable", "Iterator", "Generator", "Sequence",
        "Mapping", "MutableMapping", "MutableSequence", "Awaitable", "Coroutine", "AsyncIterator", "Literal",
        "ClassVar", "Final", "TypeVar", "Generic", "Protocol", "NamedTuple", "TypedDict", "Self", "Path",
        "Enum", "IntEnum", "Exception", "BaseException", "OrderedDict", "defaultdict", "Counter", "deque",
        "datetime", "date", "timedelta", "Decimal", "Pattern", "Match", "NoReturn", "Collection", "Hashable",
        "ABC", "Logger", "Lock", "Thread", "IO", "TextIO", "BinaryIO", "AnyStr", "Annotated", "Never"
    ]

    private static let javascriptTypes: Set<String> = [
        "Array", "Map", "Set", "WeakMap", "WeakSet", "Promise", "PromiseLike", "Record", "Partial", "Required",
        "Readonly", "ReadonlyArray", "Pick", "Omit", "Exclude", "Extract", "NonNullable", "ReturnType",
        "Parameters", "InstanceType", "Awaited", "Error", "Date", "RegExp", "Object", "JSON", "Math", "Number",
        "String", "Boolean", "Symbol", "BigInt", "Function", "Iterable", "Iterator", "AsyncIterable",
        "AsyncIterator", "IterableIterator", "Generator", "AsyncGenerator", "ArrayBuffer", "Uint8Array",
        "Int32Array", "Float64Array", "DataView", "URL", "URLSearchParams", "Buffer", "Intl", "Reflect", "Proxy",
        "console", "Infinity", "NaN", "Event", "EventTarget", "HTMLElement", "Element", "Node", "Document",
        "Window", "Response", "Request", "Headers", "AbortController", "AbortSignal", "TextEncoder", "TextDecoder",
        "NodeJS", "Uppercase", "Lowercase", "Capitalize", "ThisType", "PropertyKey", "TemplateStringsArray"
    ]
}
