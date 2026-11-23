import Foundation
import BouncerCore
import BouncerMCP
import BouncerReporting

/// A tool call's arguments, read with clear errors for the wrong type.
struct ToolArguments: Sendable {
    /// The raw arguments.
    let values: [String: JSONValue]

    /// A string argument.
    ///
    /// - Parameter key: The argument's name.
    /// - Returns: The string, or `nil` when it's absent or null.
    /// - Throws: `ToolError` when it isn't a string.
    func string(_ key: String) throws -> String? {
        guard let value = present(key) else { return nil }
        guard let string = value.stringValue else { throw ToolError("\(key) must be a string.") }
        return string
    }

    /// An argument that's a string or an array of strings.
    ///
    /// - Parameter key: The argument's name.
    /// - Returns: The strings, or none when it's absent.
    /// - Throws: `ToolError` when it's neither.
    func strings(_ key: String) throws -> [String] {
        guard let value = present(key) else { return [] }
        if let string = value.stringValue { return [string] }
        let strings = value.arrayValue?.compactMap(\.stringValue)
        guard let strings, strings.count == value.arrayValue?.count else {
            throw ToolError("\(key) must be a string or an array of strings.")
        }
        return strings
    }

    /// A Boolean argument.
    ///
    /// - Parameter key: The argument's name.
    /// - Returns: The Boolean, or `false` when it's absent.
    /// - Throws: `ToolError` when it isn't a Boolean.
    func bool(_ key: String) throws -> Bool {
        guard let value = present(key) else { return false }
        guard let bool = value.boolValue else { throw ToolError("\(key) must be true or false.") }
        return bool
    }

    /// A string argument that must name one of some choices.
    ///
    /// - Parameters:
    ///   - key: The argument's name.
    ///   - choices: The choices.
    /// - Returns: The choice, or `nil` when it's absent.
    /// - Throws: `ToolError` when it names none of them.
    func choice<Choice: RawRepresentable>(_ key: String, among choices: [Choice]) throws -> Choice?
    where Choice.RawValue == String {
        guard let raw = try string(key) else { return nil }
        guard let choice = choices.first(where: { $0.rawValue == raw.lowercased() }) else {
            throw ToolError("\(key) must be one of: \(choices.map(\.rawValue).joined(separator: ", ")).")
        }
        return choice
    }

    /// The finding offset a `cursor` argument encodes.
    ///
    /// - Returns: The offset, or 0 when there's no cursor.
    /// - Throws: `ToolError` when the cursor isn't one a response handed out.
    func cursorOffset() throws -> Int {
        guard let cursor = try string("cursor") else { return 0 }
        guard let offset = FindingCursor.decode(cursor) else {
            throw ToolError("cursor \(cursor) isn't valid; pass the cursor a findings response ended with.")
        }
        return offset
    }

    /// The `rule`, `path`, and `severity` filters.
    ///
    /// - Returns: The selection, unpaged.
    /// - Throws: `ToolError` for an argument of the wrong type or an unknown severity.
    func selection() throws -> FindingSelection {
        var selection = FindingSelection()
        (selection.rules, selection.paths) = (try strings("rule"), try strings("path"))
        selection.minimumSeverity = try choice("severity", among: [Severity.info, .warning, .error])
        return selection
    }

    /// The response budget from `max_tokens` and `max_chars`.
    var budget: ResponseBudget { ResponseBudget(arguments: values) }

    /// An argument's value, treating null as absent.
    ///
    /// - Parameter key: The argument's name.
    /// - Returns: The value.
    private func present(_ key: String) -> JSONValue? {
        guard let value = values[key], value != .null else { return nil }
        return value
    }
}
