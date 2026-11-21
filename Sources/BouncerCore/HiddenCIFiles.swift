import Foundation

/// The CI files inside a hidden `.github` folder that `review`'s directory walk lists, and the only rules
/// allowed to report in them.
///
/// The walk skips hidden folders, so workflows used to go unreviewed. Listing them for every rule would
/// bury the supply-chain findings under long YAML lines and repeated steps, so only these rules see them.
/// A workflow `check` is given directly, such as a staged one, still gets every rule, as before.
public enum HiddenCIFiles {
    /// The rules that report in a walked CI file.
    public static let ruleIDs: Set<String> = ["pipe-to-shell", "unpinned-ci-action"]

    /// The hidden folder the walk descends into.
    static let folder = ".github"

    /// Reports whether a path below the walk's root is inside a `.github` folder.
    ///
    /// - Parameter components: The path's components relative to the walk's root.
    /// - Returns: Whether any folder on the path is `.github`.
    static func isInside(_ components: [String]) -> Bool {
        components.dropLast().contains(folder)
    }

    /// Reports whether a path inside a `.github` folder is a CI file: a workflow (`workflows/*.yml` or
    /// `*.yaml`) or an action definition (`action.yml` or `action.yaml`, at any depth).
    ///
    /// - Parameter components: The path's components relative to the walk's root.
    /// - Returns: Whether the file is a workflow or an action.
    static func isCIFile(_ components: [String]) -> Bool {
        guard let name = components.last, name.hasSuffix(".yml") || name.hasSuffix(".yaml") else { return false }
        let parent = components.dropLast().last
        return parent == "workflows" || name == "action.yml" || name == "action.yaml"
    }
}
