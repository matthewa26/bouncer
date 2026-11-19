/// Measures how far a member chain such as `order.customer().address().city()` reaches past the object
/// it starts from, for the `law-of-demeter` rule.
///
/// The first object is a friend: a local, parameter, or (after `self.`/`this.`) a field. Each further
/// step talks to a stranger that some other object handed back. To stay precise, a chain isn't measured
/// when it starts from a type, module, or literal (an uppercase name, or no plain name), when any step is a
/// collection pipeline, promise, string, or builder method (`map`, `then`, `trim`, `withX`, `setX`, …), or
/// when no stranger is ever called, which leaves plain data paths like `config.server.port` alone. Trailing
/// accessors such as `count` or `isEmpty` don't add a step.
public enum DemeterChain {
    /// One member access in a chain.
    public struct Segment: Sendable, Equatable {
        public let name: String
        public let isCall: Bool

        /// Creates a segment.
        ///
        /// - Parameters:
        ///   - name: The member's name.
        ///   - isCall: Whether the member is called rather than read.
        public init(name: String, isCall: Bool) {
            self.name = name
            self.isCall = isCall
        }
    }

    private static let selfNames: Set<String> = ["self", "this", "super", "cls"]
    private static let trailingAccessors: Set<String> = [
        "count", "length", "size", "isEmpty", "first", "last", "description", "toString", "string", "value"
    ]
    private static let fluentPrefixes = [
        "with", "set", "add", "and", "or", "build", "to", "as", "is", "has", "map", "filter", "appending", "starts",
        "ends", "contains", "replacing", "removing", "adding", "trimming", "padding"
    ]
    private static let fluentNames: Set<String> = [
        "flatMap", "compactMap", "reduce", "forEach", "sorted", "sort", "reversed", "joined", "join", "split",
        "enumerated", "zip", "prefix", "suffix", "dropFirst", "dropLast", "lazy", "contains", "min", "max", "then",
        "catch", "finally", "pipe", "subscribe", "sink", "store", "assign", "eraseToAnyPublisher", "receive",
        "select", "where", "orderBy", "groupBy", "limit", "offset", "slice", "concat", "find", "some", "every",
        "includes", "keys", "values", "entries", "items", "strip", "lower", "upper", "replace", "format", "trim",
        "trimmingCharacters", "replacingOccurrences", "components", "appending", "lowercased", "uppercased",
        "expect", "should", "call", "apply", "bind", "lock", "unlock", "get", "sum", "append", "insert",
        "remove", "update", "copy", "first", "last", "index", "next", "fetch", "exec", "execute", "query",
        "advanced", "startswith", "endswith", "decode", "encode", "hash"
    ]

    /// Measures a chain's reach.
    ///
    /// - Parameters:
    ///   - base: The name the chain starts from, or `nil` if it starts from a literal or other expression.
    ///   - segments: The member accesses after it, in order.
    ///   - uppercaseIsType: Whether an uppercase member names a type (as in Swift, TS, and Python, where
    ///     `pkg.models.User()` constructs one) rather than an exported member (as in Go); such chains are skipped.
    /// - Returns: How many steps it takes past the first object, or 0 if the chain isn't measured.
    public static func reach(base: String?, segments: [Segment], uppercaseIsType: Bool = true) -> Int {
        guard let base, let first = base.first, !first.isUppercase, first != "$" else { return 0 }
        var steps = selfNames.contains(base) ? Array(segments.dropFirst()) : segments
        while let last = steps.last, trailingAccessors.contains(last.name) { steps.removeLast() }
        let namesType = uppercaseIsType && steps.contains { $0.name.first?.isUppercase == true }
        guard !namesType, !steps.contains(where: isFluent), steps.dropFirst().contains(where: \.isCall) else {
            return 0
        }
        return steps.count - 1
    }

    /// Reports whether a step is a pipeline, promise, string, or builder method, which hands back the same
    /// kind of object rather than a stranger.
    ///
    /// - Parameter segment: The step.
    /// - Returns: Whether it's fluent.
    private static func isFluent(_ segment: Segment) -> Bool {
        if fluentNames.contains(segment.name) { return true }
        return fluentPrefixes.contains { prefix in
            segment.name.hasPrefix(prefix) && segment.name.dropFirst(prefix.count).first?.isUppercase != false
        }
    }
}
