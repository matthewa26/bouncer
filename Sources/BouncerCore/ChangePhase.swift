import Foundation

/// Runs rules over what a commit is about to change rather than over the files alone, such as an
/// oversized diff or a function that got more complex than on the base branch.
///
/// The engine runs it after the main pass in `check`, independent of the project pass, so these rules
/// don't need `project.inCheck`.
public protocol ChangeAnalyzer: Sendable {
    /// Finds problems with the change being checked.
    ///
    /// - Parameters:
    ///   - files: The files being checked, as the main pass read them.
    ///   - context: Repo-wide state, including every rule's resolved settings.
    /// - Returns: The findings, each in one of `files` where possible.
    func findings(for files: [SourceFile], context: AnalysisContext) -> [Finding]
}
