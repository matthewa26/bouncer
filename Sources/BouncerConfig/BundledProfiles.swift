/// Looks up a bundled preset by name, for `--profile`/`"profile"` in `.bouncer`.
public enum BundledProfiles {
    /// Every bundled preset's name, in listing order.
    public static let names = ["kirby"]

    /// Returns a bundled preset's config, or `BouncerConfig.empty` if unnamed or unrecognized.
    ///
    /// Prefer `ProfileStore.config(named:)`, which also finds profile files and rejects unknown names.
    ///
    /// - Parameter name: The profile's name, such as `"kirby"`.
    /// - Returns: The preset's config, applied as the base layer beneath everything else.
    public static func profile(named name: String?) -> BouncerConfig {
        name.flatMap(config(named:)) ?? .empty
    }

    /// Returns a bundled preset's config, or `nil` if no preset has that name.
    ///
    /// - Parameter name: The profile's name, such as `"kirby"`.
    /// - Returns: The preset's config, or `nil` when unrecognized.
    public static func config(named name: String) -> BouncerConfig? {
        switch name {
        case "kirby": return KirbyProfile.config
        default: return nil
        }
    }
}
