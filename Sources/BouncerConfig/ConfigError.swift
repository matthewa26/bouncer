import Foundation

/// Why a `.bouncer` file that decoded is still unusable.
public enum ConfigError: Error, Equatable, CustomStringConvertible, LocalizedError {
    /// `jobs` is below one.
    case invalidJobs(path: String, value: Int)

    /// A human-readable explanation, shown by the CLI when the error ends a command.
    public var description: String {
        switch self {
        case .invalidJobs(let path, let value):
            return "\(path): \"jobs\" must be at least 1, found \(value)."
        }
    }

    /// The same text as `description`, for `localizedDescription`.
    public var errorDescription: String? { description }
}
