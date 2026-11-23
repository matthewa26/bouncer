import Foundation

/// Finds unpinned dependencies in a `composer.json`'s `require` and `require-dev`.
///
/// Judged like `package.json`, since `composer.lock` pins ordinary constraints: `*` accepts any version, a
/// `>=`/`>` alternative with no `<` has no upper bound, and a development branch (`dev-main`, or a branch alias
/// such as `2.x-dev`) moves under the lockfile on every `composer update`. A branch pinned to a commit
/// (`dev-main#<sha>`) is accepted, since Composer installs that commit. A stability flag (`^1.2@beta`) and an
/// inline alias (`dev-main as 1.0.x-dev`, judged by its real branch) don't change the verdict. Platform
/// requirements, the names without a `/` (`php`, `ext-json`), aren't packages and are never flagged.
enum ComposerPins {
    /// The sections listing required packages.
    static let sections = ["require", "require-dev"]
    /// What a development branch's constraint starts or ends with.
    private static let branchPrefix = "dev-", branchSuffix = "-dev"
    private static let anyVersion: Set = ["", "*", "x", "X"]
    private static let commit = TextMatching.regex(#"^[0-9a-fA-F]{7,40}$"#)

    /// Lists the manifest's unpinned dependencies.
    ///
    /// - Parameter text: The manifest's text.
    /// - Returns: The problems, or none if it isn't a JSON object.
    static func problems(in text: String) -> [PinProblem] {
        NPMPins.problems(in: text, sections: sections) { name, spec in
            name.contains("/") ? reason(for: spec) : nil
        }
    }

    /// Explains why a package's constraint isn't reproducible.
    ///
    /// - Parameter spec: The constraint as written, such as `^1.2 || ^2.0` or `dev-main`.
    /// - Returns: The explanation, or `nil` for a constraint the lockfile pins.
    static func reason(for spec: String) -> String? {
        let actual = spec.components(separatedBy: " as ").first ?? spec
        let alternatives = actual.split(separator: "|", omittingEmptySubsequences: true).map(stable)
        if alternatives.isEmpty || alternatives.contains(where: anyVersion.contains) {
            return "accepts any version; declare a constraint such as ^1.2."
        }
        return alternatives.contains(where: isBranch)
            ? "follows a development branch; require a tagged release, or pin it with #<commit-sha>."
            : rangeReason(alternatives)
    }

    /// Explains why a constraint's alternatives have no upper bound.
    ///
    /// - Parameter alternatives: The constraint's alternatives, without stability flags.
    /// - Returns: The explanation, or `nil` when every alternative is bounded.
    private static func rangeReason(_ alternatives: [String]) -> String? {
        let unbounded = alternatives.contains { $0.hasPrefix(">") && !$0.contains("<") }
        return unbounded ? "has no upper bound, so any future major version is accepted; add one, such as <3." : nil
    }

    /// Drops an alternative's stability flag and surrounding spaces.
    ///
    /// - Parameter alternative: One `|`-separated alternative, such as ` ^1.2@beta`.
    /// - Returns: The constraint, such as `^1.2`.
    private static func stable(_ alternative: Substring) -> String {
        let trimmed = alternative.trimmingCharacters(in: .whitespaces)
        return String(trimmed.prefix { $0 != "@" })
    }

    /// Reports whether an alternative follows a branch that isn't pinned to a commit.
    ///
    /// - Parameter constraint: One alternative, such as `dev-main` or `0.2.x-dev#abc1234`.
    /// - Returns: Whether it's an unpinned development branch.
    private static func isBranch(_ constraint: String) -> Bool {
        let parts = constraint.split(separator: "#", maxSplits: 1).map(String.init)
        guard let branch = parts.first, branch.hasPrefix(branchPrefix) || branch.hasSuffix(branchSuffix) else {
            return false
        }
        return parts.count < 2 || !TextMatching.matches(commit, parts[1])
    }
}
