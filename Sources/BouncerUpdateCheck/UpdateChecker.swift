import Foundation

/// The locally cached result of the last successful update check.
struct UpdateCheckCache: Codable {
    let lastCheckedAt: Date
    let latestKnownSHA: String
    let latestKnownTag: String
}

/// The outcome of one update check.
public struct UpdateCheckResult: Sendable, Equatable {
    /// Whether the latest known release differs from the installed build.
    public let updateAvailable: Bool
    /// The latest known release's tag, if a check has ever succeeded.
    public let latestTag: String?
}

/// Compares the installed build against the latest GitHub release, with local caching.
///
/// Never throws: any network failure is swallowed and treated as "no update
/// known," since the update check must never block or fail an analysis run.
public struct UpdateChecker {
    private let lookup: GitHubReleaseLookup
    private let cachePath: URL
    private let currentSHA: String
    private let repo: String
    private let intervalHours: Int
    private let now: @Sendable () -> Date

    /// Creates an update checker.
    ///
    /// - Parameters:
    ///   - lookup: Fetches the latest release from GitHub.
    ///   - cachePath: Where the last check's result is cached.
    ///   - currentSHA: The installed build's embedded commit SHA.
    ///   - repo: The repository to check, as `"owner/name"`.
    ///   - intervalHours: How long a cached result stays valid.
    ///   - now: The current time, overridable for tests.
    public init(
        lookup: GitHubReleaseLookup, cachePath: URL, currentSHA: String, repo: String,
        intervalHours: Int = 24, now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.lookup = lookup
        self.cachePath = cachePath
        self.currentSHA = currentSHA
        self.repo = repo
        self.intervalHours = intervalHours
        self.now = now
    }

    /// Checks for an update, using the cache if it's still fresh.
    ///
    /// - Returns: Whether an update is available, and the latest known tag.
    public func check() async -> UpdateCheckResult {
        if let cached = readCache(), !isStale(cached) {
            return result(sha: cached.latestKnownSHA, tag: cached.latestKnownTag)
        }
        return await refreshAndCheck()
    }

    /// Fetches the latest release, caches it, and falls back to any existing cache on failure.
    ///
    /// - Returns: Whether an update is available, and the latest known tag.
    private func refreshAndCheck() async -> UpdateCheckResult {
        guard let release = try? await lookup.latestRelease(repo: repo) else {
            guard let cached = readCache() else { return UpdateCheckResult(updateAvailable: false, latestTag: nil) }
            return result(sha: cached.latestKnownSHA, tag: cached.latestKnownTag)
        }
        let cache = UpdateCheckCache(
            lastCheckedAt: now(), latestKnownSHA: release.commitSHA, latestKnownTag: release.tagName
        )
        writeCache(cache)
        return result(sha: release.commitSHA, tag: release.tagName)
    }

    /// Builds a result by comparing a known SHA against the installed build's SHA.
    ///
    /// - Parameters:
    ///   - sha: The latest known release's commit SHA.
    ///   - tag: The latest known release's tag.
    /// - Returns: The comparison result.
    private func result(sha: String, tag: String) -> UpdateCheckResult {
        UpdateCheckResult(updateAvailable: sha != currentSHA, latestTag: tag)
    }

    /// Reads the cached check result, if present and valid.
    ///
    /// - Returns: The cached result, or `nil` if absent or unreadable.
    private func readCache() -> UpdateCheckCache? {
        guard let data = try? Data(contentsOf: cachePath) else { return nil }
        return try? JSONDecoder().decode(UpdateCheckCache.self, from: data)
    }

    /// Writes a check result to the cache, ignoring any write failure.
    ///
    /// - Parameter cache: The result to persist.
    private func writeCache(_ cache: UpdateCheckCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cachePath)
    }

    /// Reports whether a cached result is older than the configured interval.
    ///
    /// - Parameter cache: The cached result to check.
    /// - Returns: Whether the cache has expired.
    private func isStale(_ cache: UpdateCheckCache) -> Bool {
        now().timeIntervalSince(cache.lastCheckedAt) > Double(intervalHours) * 3600
    }
}
