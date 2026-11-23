import Foundation
import BouncerCore

/// What the project pass reads from a `composer.json`: its PSR-4 autoload prefixes and the packages it
/// requires.
///
/// `autoload` and `autoload-dev` both count, since tests import the code they test. A `psr-4` value is a folder
/// or a list of folders; `classmap`, `psr-0`, and `files` entries aren't read (`files` are loaded on every
/// request, so they aren't any one file's dependency). Requirements without a `/` (`php`, `ext-json`,
/// `composer-plugin-api`) are the platform, not packages, and are left out.
struct ComposerManifest {
    /// One PSR-4 rule: a namespace prefix and the folders its classes live under.
    struct Prefix: Equatable {
        /// The prefix with its trailing `\`, such as `App\`; `""` is the fallback for every namespace.
        let namespace: String
        /// Repo-relative folders, without `./` or a trailing `/`; `""` is the manifest's own folder.
        let directories: [String]
    }

    /// The PSR-4 rules, longest prefix first, as Composer tries them.
    let prefixes: [Prefix]
    /// The names of the packages `require` and `require-dev` list, without platform requirements.
    let dependencies: [String]
    /// The autoload sections whose PSR-4 rules are read.
    private static let autoloadSections = ["autoload", "autoload-dev"]
    /// The sections listing required packages.
    static let requireSections = ["require", "require-dev"]

    /// Parses a manifest's text.
    ///
    /// - Parameter text: The `composer.json` contents.
    /// - Returns: The manifest, or `nil` if it isn't a JSON object.
    init?(text: String) {
        guard let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else {
            return nil
        }
        let rules = Self.autoloadSections.map { Self.object(Self.object(json[$0])["psr-4"]) }
        prefixes = rules.flatMap(Self.prefixes).sorted {
            ($0.namespace.count, $1.namespace) > ($1.namespace.count, $0.namespace)
        }
        dependencies = Self.requireSections.flatMap { Self.object(json[$0]).keys.sorted() }.filter(Self.isPackage)
    }

    /// Reads the manifest at a repo-relative path.
    ///
    /// - Parameters:
    ///   - path: The manifest's path, such as `composer.json`.
    ///   - repoRoot: The repository root.
    /// - Returns: The manifest, or `nil` if it's missing or malformed.
    static func read(_ path: String, repoRoot: URL) -> ComposerManifest? {
        (try? String(contentsOf: RepoPath.url(path, in: repoRoot), encoding: .utf8)).flatMap(Self.init(text:))
    }

    /// Reports whether a requirement is a package rather than the platform (`php`, `ext-*`, `lib-*`, …).
    ///
    /// - Parameter name: The requirement's name.
    /// - Returns: Whether it's `vendor/package`.
    static func isPackage(_ name: String) -> Bool {
        name.contains("/")
    }

    /// Reads a JSON value as an object.
    ///
    /// - Parameter value: Any JSON value, or `nil`.
    /// - Returns: The object, or an empty one for anything else.
    private static func object(_ value: Any?) -> [String: Any] {
        value as? [String: Any] ?? [:]
    }

    /// Reads one `psr-4` map.
    ///
    /// - Parameter map: Prefix keys to a folder or a list of folders.
    /// - Returns: Each prefix with its normalized folders.
    private static func prefixes(_ map: [String: Any]) -> [Prefix] {
        map.keys.sorted().map { key in
            let folders = (map[key] as? [String]) ?? [map[key] as? String].compactMap { $0 }
            return Prefix(namespace: key.drop { $0 == "\\" }.description, directories: folders.map(normalized))
        }
    }

    /// Normalizes a folder: no leading `./` or `/`, and no trailing `/`.
    ///
    /// - Parameter folder: The folder as written, such as `./src/`.
    /// - Returns: `src`, or `""` for the manifest's folder.
    private static func normalized(_ folder: String) -> String {
        ProjectPath.join("", folder) ?? folder
    }
}
