import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A GitHub API URL that couldn't be constructed from the given components.
struct InvalidGitHubURL: Error {
    let path: String
}

/// Looks up a repository's latest release over the network via the GitHub API.
public struct URLSessionGitHubReleaseLookup: GitHubReleaseLookup {
    private struct ReleaseResponse: Decodable { let tagName: String }
    private struct CommitResponse: Decodable { let sha: String }

    private let session: URLSession

    /// Creates a lookup backed by a `URLSession`.
    ///
    /// - Parameter session: The session to issue requests with.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches the latest release's tag, then resolves that tag to its commit SHA.
    ///
    /// - Parameter repo: The repository, as `"owner/name"`.
    /// - Returns: The latest release's tag and commit SHA.
    /// - Throws: If either network request fails or its response can't be decoded.
    public func latestRelease(repo: String) async throws -> GitHubReleaseInfo {
        let tag = try await fetchLatestTag(repo: repo)
        let sha = try await fetchCommitSHA(repo: repo, ref: tag)
        return GitHubReleaseInfo(tagName: tag, commitSHA: sha)
    }

    /// Fetches the tag name of a repository's latest release.
    ///
    /// - Parameter repo: The repository, as `"owner/name"`.
    /// - Returns: The latest release's tag name.
    /// - Throws: If the request fails or the response can't be decoded.
    private func fetchLatestTag(repo: String) async throws -> String {
        let (data, _) = try await session.data(from: makeURL("repos/\(repo)/releases/latest"))
        return try decode(ReleaseResponse.self, from: data).tagName
    }

    /// Resolves a ref (tag or branch name) to the commit SHA it points to.
    ///
    /// - Parameters:
    ///   - repo: The repository, as `"owner/name"`.
    ///   - ref: The ref to resolve.
    /// - Returns: The resolved commit SHA.
    /// - Throws: If the request fails or the response can't be decoded.
    private func fetchCommitSHA(repo: String, ref: String) async throws -> String {
        let (data, _) = try await session.data(from: makeURL("repos/\(repo)/commits/\(ref)"))
        return try decode(CommitResponse.self, from: data).sha
    }

    /// Builds a GitHub API URL from a path, failing clearly rather than crashing.
    ///
    /// - Parameter path: The API path, without the leading `https://api.github.com/`.
    /// - Returns: The constructed URL.
    /// - Throws: `InvalidGitHubURL` if the path doesn't form a valid URL.
    private func makeURL(_ path: String) throws -> URL {
        guard let url = URL(string: "https://api.github.com/\(path)") else { throw InvalidGitHubURL(path: path) }
        return url
    }

    /// Decodes a snake_case GitHub API response.
    ///
    /// - Parameters:
    ///   - type: The type to decode into.
    ///   - data: The response body.
    /// - Returns: The decoded value.
    /// - Throws: If the data isn't valid JSON matching `type`.
    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }
}
