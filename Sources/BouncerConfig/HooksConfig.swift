/// The `hooks` section of `.bouncer`.
///
/// Unlike every other section, hook lists merge additively across config
/// layers rather than override-by-more-specific: a personal global hook and a
/// repo-specific one should both run.
public struct HooksConfig: Codable, Sendable, Equatable {
    public var preCheck: [String]?
    public var postCheck: [String]?

    /// Creates a hooks config.
    ///
    /// - Parameters:
    ///   - preCheck: Commands to run before analysis, in order.
    ///   - postCheck: Commands to run after reporting, in order.
    public init(preCheck: [String]? = nil, postCheck: [String]? = nil) {
        self.preCheck = preCheck
        self.postCheck = postCheck
    }

    /// Concatenates this config's hooks with another's, this config's running first.
    ///
    /// - Parameter other: The config whose hooks run after this one's.
    /// - Returns: The combined config.
    public func merging(_ other: HooksConfig) -> HooksConfig {
        HooksConfig(
            preCheck: concatenated(preCheck, other.preCheck), postCheck: concatenated(postCheck, other.postCheck)
        )
    }

    /// Concatenates two optional lists, treating a missing list as empty.
    ///
    /// - Parameters:
    ///   - first: The list to place first.
    ///   - second: The list to place second.
    /// - Returns: The concatenated list, or `nil` if both inputs are `nil`.
    private func concatenated(_ first: [String]?, _ second: [String]?) -> [String]? {
        guard first != nil || second != nil else { return nil }
        return (first ?? []) + (second ?? [])
    }
}
