import Foundation
import BouncerCore
import BouncerConfig
import BouncerCoverage

/// Builds an `AnalysisEngine.CoverageConfiguration` from a `.bouncer` coverage section.
enum CoverageResolver {
    /// Resolves the coverage configuration to use, if coverage checking is enabled and configured.
    ///
    /// - Parameters:
    ///   - coverage: The merged `.bouncer` coverage section.
    ///   - repoRoot: The repository root, used to resolve a relative report path.
    /// - Returns: The engine's coverage configuration, or `nil` if not applicable.
    static func makeConfiguration(coverage: CoverageConfig?, repoRoot: URL) -> AnalysisEngine.CoverageConfiguration? {
        guard let coverage, coverage.enabled != false, let reportPathString = coverage.reportPath else { return nil }
        let reportPath = URL(fileURLWithPath: reportPathString, relativeTo: repoRoot)
        guard let provider = provider(format: coverage.format ?? "auto", reportPath: reportPath) else { return nil }
        let threshold = coverage.threshold ?? 80
        return AnalysisEngine.CoverageConfiguration(provider: provider, reportPath: reportPath, threshold: threshold)
    }

    /// Picks a coverage provider for a requested format, honoring platform limits.
    ///
    /// - Parameters:
    ///   - format: `"lcov"`, `"xccov"`, or `"auto"`.
    ///   - reportPath: The report's location, used by `"auto"` to sniff the format.
    /// - Returns: The matching provider, or `nil` if `"xccov"` was requested off macOS.
    private static func provider(format: String, reportPath: URL) -> CoverageProvider? {
        switch format {
        case "lcov": return LCOVCoverageProvider()
        case "xccov": return xccovProvider()
        default: return autoProvider(reportPath: reportPath)
        }
    }

    /// Sniffs a report path to pick between xccov and LCOV.
    ///
    /// - Parameter reportPath: The report's location.
    /// - Returns: An xccov provider for a `.xcresult` path on macOS, otherwise LCOV.
    private static func autoProvider(reportPath: URL) -> CoverageProvider? {
        #if os(macOS)
        if reportPath.pathExtension.lowercased() == "xcresult" { return XccovCoverageProvider() }
        #endif
        return LCOVCoverageProvider()
    }

    /// Returns the xccov provider, only where it's compiled in.
    ///
    /// - Returns: The xccov provider on macOS, otherwise `nil`.
    private static func xccovProvider() -> CoverageProvider? {
        #if os(macOS)
        return XccovCoverageProvider()
        #else
        return nil
        #endif
    }
}
