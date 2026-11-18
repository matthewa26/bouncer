/// The `updateCheck` section of `.bouncer`.
public struct UpdateCheckConfig: Codable, Sendable, Equatable {
    public var enabled: Bool?
    public var intervalHours: Int?
    public var repo: String?

    /// Creates an update-check config.
    ///
    /// - Parameters:
    ///   - enabled: Whether the pre-flight update check runs at all.
    ///   - intervalHours: How often to re-query GitHub for a new release.
    ///   - repo: The `owner/name` GitHub repository to check releases against.
    public init(enabled: Bool? = nil, intervalHours: Int? = nil, repo: String? = nil) {
        self.enabled = enabled
        self.intervalHours = intervalHours
        self.repo = repo
    }

    /// Merges another config's fields over this one's, preferring the other's when both are set.
    ///
    /// - Parameter other: The config whose fields take precedence.
    /// - Returns: The merged config.
    public func merging(_ other: UpdateCheckConfig) -> UpdateCheckConfig {
        UpdateCheckConfig(
            enabled: other.enabled ?? enabled,
            intervalHours: other.intervalHours ?? intervalHours,
            repo: other.repo ?? repo
        )
    }
}
