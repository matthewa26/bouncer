import BouncerCore

extension BouncerConfig {
    /// Works out how many files a run analyzes at once.
    ///
    /// - Parameter flag: `--jobs`, which wins when given.
    /// - Returns: `flag`, else `jobs`, else one per active processor core.
    public func jobs(overriddenBy flag: Int?) -> Int {
        flag ?? jobs ?? AnalysisEngine.defaultJobs
    }

    /// This config without the settings that change how a run goes but never what it finds: `agent`, which only
    /// changes how a long-lived session refreshes, and `jobs`, which only changes how many files are analyzed at
    /// once. A saved run is keyed by it, so editing either never discards the saved findings.
    public var findingSettings: BouncerConfig {
        var settings = self
        (settings.agent, settings.jobs) = (nil, nil)
        return settings
    }
}
