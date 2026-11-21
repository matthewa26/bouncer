import Foundation

/// Reads, merges, and writes `.bouncer`-schema files as untyped JSON, so unrelated keys survive an edit.
public enum ConfigFileJSON {
    /// Reads a config file as a JSON object, or an empty object if it doesn't exist.
    ///
    /// - Parameter path: The file to read.
    /// - Returns: The decoded JSON object.
    /// - Throws: If the file exists but isn't valid JSON.
    public static func readObject(at path: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: path) else { return [:] }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Writes a JSON object as pretty-printed, key-sorted JSON, creating the parent directory if needed.
    ///
    /// - Parameters:
    ///   - json: The object to write.
    ///   - path: The destination file.
    /// - Throws: If the object can't be serialized or the file can't be written.
    public static func write(_ json: [String: Any], to path: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        let directory = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: path)
    }

    /// Converts a typed config into the JSON object it encodes to, omitting unset sections.
    ///
    /// - Parameter config: The config to convert.
    /// - Returns: The equivalent JSON object.
    /// - Throws: If encoding fails.
    public static func object(from config: BouncerConfig) throws -> [String: Any] {
        let data = try JSONEncoder().encode(config)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Merges `overlay` into `base`, recursing into nested objects and replacing everything else.
    ///
    /// - Parameters:
    ///   - base: The existing object, whose unrelated keys are kept.
    ///   - overlay: The new values, which win on any conflict.
    /// - Returns: The merged object.
    public static func deepMerged(_ base: [String: Any], with overlay: [String: Any]) -> [String: Any] {
        base.merging(overlay) { old, new in
            guard let oldObject = old as? [String: Any], let newObject = new as? [String: Any] else { return new }
            return deepMerged(oldObject, with: newObject)
        }
    }

    /// Flattens a JSON object into sorted `dotted.path = value` lines, for summaries.
    ///
    /// - Parameters:
    ///   - json: The object to flatten.
    ///   - prefix: The dotted path of `json` itself, empty at the root.
    /// - Returns: One line per leaf value.
    public static func dottedLines(_ json: [String: Any], prefix: String = "") -> [String] {
        json.keys.sorted().flatMap { key -> [String] in
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"
            guard let nested = json[key] as? [String: Any] else { return ["\(path) = \(render(json[key]))"] }
            return dottedLines(nested, prefix: path)
        }
    }

    /// Renders one leaf JSON value as compact JSON text.
    ///
    /// - Parameter value: The leaf value.
    /// - Returns: Its JSON text, such as `25`, `true`, `"all"`, or `["a","b"]`.
    private static func render(_ value: Any?) -> String {
        guard let value,
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
        else { return "null" }
        return String(data: data, encoding: .utf8) ?? "null"
    }
}
