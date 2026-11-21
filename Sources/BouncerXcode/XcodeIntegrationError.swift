import Foundation

/// Why `bouncer xcode` couldn't find or edit a project.
public enum XcodeIntegrationError: Error, Equatable, CustomStringConvertible {
    /// The directory holds no `.xcodeproj`.
    case noProject(directory: String)
    /// The directory holds several `.xcodeproj` bundles, so `--project` must pick one.
    case severalProjects([String])
    /// Some requested targets aren't native targets of the project.
    case unknownTargets(requested: [String], available: [String])
    /// The project file couldn't be read or parsed.
    case unreadableProject(path: String, reason: String)

    /// A human-readable explanation.
    public var description: String {
        switch self {
        case let .noProject(directory):
            return "No .xcodeproj in \(directory); pass --project <path>."
        case let .severalProjects(names):
            return "Several Xcode projects here (\(names.joined(separator: ", "))); pick one with --project."
        case let .unknownTargets(requested, available):
            let targets = available.joined(separator: ", ")
            return "No target named \(requested.joined(separator: ", ")). Targets: \(targets)."
        case let .unreadableProject(path, reason):
            return "Couldn't read \(path): \(reason)"
        }
    }
}

/// Finds the Xcode project `bouncer xcode` should edit.
public enum XcodeProjectLocator {
    /// Lists the `.xcodeproj` bundles directly inside a directory, sorted by name.
    ///
    /// - Parameter directory: The directory to look in.
    /// - Returns: The projects found.
    public static func candidates(in directory: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".xcodeproj") }.sorted().map { directory.appendingPathComponent($0) }
    }

    /// Picks the project: the one given, or the only one in the directory.
    ///
    /// - Parameters:
    ///   - explicitPath: The `--project` path, resolved against `directory`, or `nil` to search.
    ///   - directory: The directory to search, normally the current one.
    /// - Returns: The project bundle.
    /// - Throws: `XcodeIntegrationError.noProject` or `.severalProjects` when the search doesn't find exactly one.
    public static func locate(explicitPath: String?, in directory: URL) throws -> URL {
        if let explicitPath { return resolve(explicitPath, in: directory) }
        let found = candidates(in: directory)
        guard found.count == 1 else {
            if found.isEmpty { throw XcodeIntegrationError.noProject(directory: directory.path) }
            throw XcodeIntegrationError.severalProjects(found.map(\.lastPathComponent))
        }
        return found[0]
    }

    /// Resolves a `--project` path.
    ///
    /// - Parameters:
    ///   - path: An absolute path, or one relative to `directory`.
    ///   - directory: The directory relative paths start from.
    /// - Returns: The standardized project URL.
    private static func resolve(_ path: String, in directory: URL) -> URL {
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : directory.appendingPathComponent(path)
        return url.standardizedFileURL
    }
}
