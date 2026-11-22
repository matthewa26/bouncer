import BouncerCore

/// The `output` section of `.bouncer`.
public struct OutputConfig: Codable, Sendable, Equatable {
    public var verbosity: OutputVerbosity?
    public var color: Bool?
    /// Whether `review` saves its result to `.bouncer-cache/last-run.json` and starts the next run from it;
    /// `nil` means on.
    public var saveRun: Bool?

    /// Creates an output config.
    ///
    /// - Parameters:
    ///   - verbosity: How much detail console output should include.
    ///   - color: Whether console output should be colored.
    ///   - saveRun: Whether `review` saves its result for the next run, or `nil` for the default (on).
    public init(verbosity: OutputVerbosity? = nil, color: Bool? = nil, saveRun: Bool? = nil) {
        self.verbosity = verbosity
        self.color = color
        self.saveRun = saveRun
    }

    /// Merges another config's fields over this one's, preferring the other's when both are set.
    ///
    /// - Parameter other: The config whose fields take precedence.
    /// - Returns: The merged config.
    public func merging(_ other: OutputConfig) -> OutputConfig {
        OutputConfig(
            verbosity: other.verbosity ?? verbosity, color: other.color ?? color, saveRun: other.saveRun ?? saveRun
        )
    }
}
