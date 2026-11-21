import Foundation

/// Applies a `--set key.path=value` edit to a JSON object tree.
enum DottedPathJSON {
    /// Sets a value at a dotted path within a JSON dictionary, creating nested dictionaries as needed.
    ///
    /// - Parameters:
    ///   - path: The dotted key path, such as `"coverage.threshold"`.
    ///   - value: The raw string value, parsed into a bool, int, double, or string.
    ///   - root: The JSON dictionary to edit.
    /// - Returns: The updated dictionary.
    static func apply(path: String, value: String, to root: [String: Any]) -> [String: Any] {
        setValue(keys: path.split(separator: ".").map(String.init), value: parseValue(value), in: root)
    }

    /// Sets a string at a dotted path, without inferring a bool or number from it.
    ///
    /// For values that must stay strings, such as a profile named `"2024"`.
    ///
    /// - Parameters:
    ///   - path: The dotted key path, such as `"profile"`.
    ///   - value: The string to store as-is.
    ///   - root: The JSON dictionary to edit.
    /// - Returns: The updated dictionary.
    static func applyString(path: String, value: String, to root: [String: Any]) -> [String: Any] {
        setValue(keys: path.split(separator: ".").map(String.init), value: value, in: root)
    }

    /// Recursively sets a value at a key path, building intermediate dictionaries as needed.
    ///
    /// - Parameters:
    ///   - keys: The remaining path segments.
    ///   - value: The value to set at the final segment.
    ///   - dict: The dictionary to update at this level.
    /// - Returns: The updated dictionary.
    private static func setValue(keys: [String], value: Any, in dict: [String: Any]) -> [String: Any] {
        var dict = dict
        guard let first = keys.first else { return dict }
        if keys.count == 1 {
            dict[first] = value
            return dict
        }
        let nested = (dict[first] as? [String: Any]) ?? [:]
        dict[first] = setValue(keys: Array(keys.dropFirst()), value: value, in: nested)
        return dict
    }

    /// Infers a JSON-compatible type from a raw command-line string.
    ///
    /// - Parameter raw: The raw value text.
    /// - Returns: A `Bool`, `Int`, `Double`, or the original `String`.
    private static func parseValue(_ raw: String) -> Any {
        if raw == "true" { return true }
        if raw == "false" { return false }
        if let intValue = Int(raw) { return intValue }
        if let doubleValue = Double(raw) { return doubleValue }
        return raw
    }
}
