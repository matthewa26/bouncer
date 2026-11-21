#if canImport(XcodeProj)
import XcodeProj
#endif

/// Adds Bouncer to Xcode projects as a build step. Xcode projects only exist on macOS, so the rest of this
/// module is compiled there alone.
public enum XcodeIntegration {
    /// Whether this build can edit Xcode projects: true on macOS, false on Linux and Windows.
    public static var isSupported: Bool {
        #if canImport(XcodeProj)
        true
        #else
        false
        #endif
    }
}
