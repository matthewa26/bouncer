import BouncerCore

/// Settings for the project pass: rules over the whole codebase, such as import cycles and unused exports.
public struct ProjectConfig: Codable, Sendable, Equatable {
    /// Whether `bouncer check` also runs project rules, indexing the whole repo. `review` always does.
    public var inCheck: Bool?

    /// Creates a project config.
    ///
    /// - Parameter inCheck: Whether `check` runs project rules; `nil` leaves it to lower layers (default off).
    public init(inCheck: Bool? = nil) {
        self.inCheck = inCheck
    }

    /// Overlays a higher-precedence layer's settings.
    ///
    /// - Parameter other: The higher-precedence layer.
    /// - Returns: The merged config.
    public func merging(_ other: ProjectConfig) -> ProjectConfig {
        ProjectConfig(inCheck: other.inCheck ?? inCheck)
    }
}
