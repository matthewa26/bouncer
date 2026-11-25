import Foundation

/// The dependency lockfiles package managers and infrastructure tools write, which Bouncer leaves out of
/// analysis: they're generated, so nothing in them can be fixed by hand.
public enum Lockfiles {
    /// The lockfiles' names: npm, Yarn, pnpm, Bun, Composer, Bundler, Poetry, Pipenv, uv, Cargo, Go, SwiftPM,
    /// NuGet, Dart, mise, Nix, Terraform and OpenTofu (`.terraform.lock.hcl`), and the AWS CDK's cached context.
    public static let names: Set<String> = [
        "package-lock.json", "npm-shrinkwrap.json", "yarn.lock", "pnpm-lock.yaml", "bun.lock", "bun.lockb",
        "composer.lock", "Gemfile.lock", "poetry.lock", "Pipfile.lock", "uv.lock", "Cargo.lock", "go.sum",
        "Package.resolved", "packages.lock.json", "pubspec.lock", "mise.lock", "flake.lock", ".terraform.lock.hcl",
        "cdk.context.json"
    ]

    /// Checks whether a path is a lockfile, by its name.
    ///
    /// - Parameter url: The path to check.
    /// - Returns: Whether the file is one of the lockfiles.
    public static func contains(_ url: URL) -> Bool {
        names.contains(url.lastPathComponent)
    }
}
