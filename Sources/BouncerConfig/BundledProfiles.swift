/// Looks up a bundled preset by name, for `--profile`/`"profile"` in `.bouncer`.
public enum BundledProfiles {
    /// Returns a bundled preset's config, or `BouncerConfig.empty` if unnamed or unrecognized.
    ///
    /// - Parameter name: The profile's name, such as `"kirby"`.
    /// - Returns: The preset's config, applied as the base layer beneath everything else.
    public static func profile(named name: String?) -> BouncerConfig {
        switch name {
        case "kirby": return KirbyProfile.config
        default: return .empty
        }
    }
}
