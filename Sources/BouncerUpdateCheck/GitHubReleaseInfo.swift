/// The pieces of a GitHub release Bouncer's update check needs.
public struct GitHubReleaseInfo: Sendable, Equatable {
    /// The release's tag name, such as `"v0.1.0"`.
    public let tagName: String
    /// The commit SHA the release's tag points to.
    public let commitSHA: String

    /// Creates a release info value.
    ///
    /// - Parameters:
    ///   - tagName: The release's tag name.
    ///   - commitSHA: The commit SHA the release's tag points to.
    public init(tagName: String, commitSHA: String) {
        self.tagName = tagName
        self.commitSHA = commitSHA
    }
}

/// Looks up the latest release of a GitHub repository.
public protocol GitHubReleaseLookup: Sendable {
    /// Fetches the latest release's tag and commit SHA.
    ///
    /// - Parameter repo: The repository, as `"owner/name"`.
    /// - Returns: The latest release's info.
    /// - Throws: If the network request fails or the response can't be parsed.
    func latestRelease(repo: String) async throws -> GitHubReleaseInfo
}
