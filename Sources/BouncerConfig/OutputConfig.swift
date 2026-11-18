import BouncerCore

/// The `output` section of `.bouncer`.
public struct OutputConfig: Codable, Sendable, Equatable {
    public var verbosity: OutputVerbosity?
    public var color: Bool?

    /// Creates an output config.
    ///
    /// - Parameters:
    ///   - verbosity: How much detail console output should include.
    ///   - color: Whether console output should be colored.
    public init(verbosity: OutputVerbosity? = nil, color: Bool? = nil) {
        self.verbosity = verbosity
        self.color = color
    }

    /// Merges another config's fields over this one's, preferring the other's when both are set.
    ///
    /// - Parameter other: The config whose fields take precedence.
    /// - Returns: The merged config.
    public func merging(_ other: OutputConfig) -> OutputConfig {
        OutputConfig(verbosity: other.verbosity ?? verbosity, color: other.color ?? color)
    }
}
