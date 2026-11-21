import Foundation

/// Why a named profile couldn't be resolved, loaded, or changed.
public enum ProfileError: Error, Equatable, CustomStringConvertible, LocalizedError {
    /// The name has characters outside `[A-Za-z0-9._-]`, or is `.`/`..`.
    case invalidName(String)
    /// No profile file or bundled preset has this name; `searched` lists where Bouncer looked.
    case notFound(name: String, searched: [String])
    /// A profile file declares hooks, which only a trust-gated `.bouncer` may do.
    case containsHooks(path: String)
    /// A profile file names another profile, which would make profiles recursive.
    case containsProfileKey(path: String)
    /// A bundled preset was asked to be deleted or overwritten.
    case bundled(String)

    /// A human-readable explanation, shown by the CLI when the error ends a command.
    public var description: String {
        switch self {
        case .invalidName(let name):
            return "Invalid profile name \"\(name)\": use only letters, digits, '.', '_', and '-'."
        case .notFound(let name, let searched):
            return "Unknown profile \"\(name)\". Looked in: \(searched.joined(separator: ", "))."
        case .containsHooks(let path):
            return "Profile \(path) declares hooks. Hooks belong in a .bouncer file, where the trust gate applies."
        case .containsProfileKey(let path):
            return "Profile \(path) sets \"profile\"; a profile can't select another profile."
        case .bundled(let name):
            return "\"\(name)\" is a bundled profile and can't be changed or deleted."
        }
    }

    /// The same text as `description`, for `localizedDescription`.
    public var errorDescription: String? { description }
}
