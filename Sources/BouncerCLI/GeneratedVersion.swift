/// The installed build's version and origin commit, baked in at release time.
///
/// `Scripts/generate-version.sh` overwrites this file as part of cutting a
/// tagged release, so a Homebrew from-source build carries its true origin
/// commit. This checked-in copy is the development placeholder.
enum GeneratedVersion {
    static let versionString = "0.0.0-dev"
    static let commitSHA = "development"
}
