import Foundation
import BouncerCore

/// Flags a block of code copied into another file, exactly or with renamed identifiers and changed literals.
///
/// Each file is tokenized without whitespace or comments, with identifiers and literals normalized, and
/// fingerprinted by winnowing (see `CloneFingerprinter`); the fingerprints are cached with the file's facts.
/// Shared fingerprints are merged into maximal regions, and regions of at least `minTokens` tokens and
/// `minLines` lines are grouped into clone classes. Each copy but the first (by path, then line) gets one
/// finding naming the first; when only the first copy is being checked, it's reported there instead. Copies
/// within one file are left to `duplicate-block`. Covers Swift, TypeScript/JavaScript, Python, and Go.
public struct DuplicateCodeRule: ProjectRule {
    public let id = "duplicate-code"
    static let defaultMinTokens = 50
    static let defaultMinLines = 6

    /// Creates the rule.
    public init() {}

    /// Fingerprints a file, reusing cached fingerprints made with the current settings.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - cached: Fingerprints cached for the file's current contents.
    ///   - context: Repo-wide state, for this rule's `ignoreLiterals` setting.
    /// - Returns: The fingerprints, or `nil` for a language that isn't tokenized; while the rule is off,
    ///   whatever was cached, so turning it back on starts warm.
    func cloneFacts(for file: SourceFile, cached: CloneFacts?, context: AnalysisContext) -> CloneFacts? {
        let settings = context.settings(for: id)
        guard settings.enabled else { return cached }
        let keepLiterals = !settings.parameters.bool("ignoreLiterals", default: true)
        let scheme = CloneFingerprinter.scheme(keepLiterals: keepLiterals)
        if cached?.scheme == scheme { return cached }
        let tokens = CloneTokenizer.tokens(of: file, keepLiterals: keepLiterals)
        return tokens.map { CloneFingerprinter.fingerprints(of: $0, scheme: scheme) }
    }

    /// Finds code duplicated across files and reports each copy once.
    ///
    /// - Parameters:
    ///   - index: The project's facts, with fingerprints.
    ///   - targets: The paths being checked; only copies in these are reported.
    ///   - context: Repo-wide state, with `minTokens`, `minLines`, and `ignore`.
    /// - Returns: One finding per reported copy.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let parameters = context.settings(for: id).parameters
        let files = compared(index, ignoring: parameters.stringList("ignore", default: []))
        let minTokens = parameters.int("minTokens", default: Self.defaultMinTokens)
        let minLines = parameters.int("minLines", default: Self.defaultMinLines)
        let regions = CloneMatcher(files: files).regions().filter {
            $0.tokens >= minTokens && min($0.first.codeLines, $0.second.codeLines) >= minLines
        }
        return CloneClasses.group(regions).flatMap { findings(for: $0, targets: targets, context: context) }
    }

    /// Lists the files to compare: every indexed file not matching an `ignore` glob, sorted by path.
    ///
    /// - Parameters:
    ///   - index: The project's facts.
    ///   - ignore: Globs for generated or vendored files the exclude list doesn't already cover.
    /// - Returns: The files.
    private func compared(_ index: ProjectIndex, ignoring ignore: [String]) -> [FileFacts] {
        index.facts.values.filter { file in
            !ignore.contains { GlobMatcher.matches(path: file.path, pattern: $0) }
        }.sorted { $0.path < $1.path }
    }

    /// Reports a clone class's copies in target files, each naming the first copy.
    ///
    /// - Parameters:
    ///   - clones: The class.
    ///   - targets: The paths being checked.
    ///   - context: Repo-wide state, for the repo root and severity.
    /// - Returns: The findings.
    private func findings(for clones: CloneClass, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let first = clones.members[0]
        let others = clones.members.filter { $0.path != first.path }
        guard let second = others.first else { return [] }
        let reported = others.filter { targets.contains($0.path) }
        if reported.isEmpty && targets.contains(first.path) {
            return [finding(at: first, copying: second, in: clones, context: context)]
        }
        return reported.map { finding(at: $0, copying: first, in: clones, context: context) }
    }

    /// Builds one copy's finding.
    ///
    /// - Parameters:
    ///   - copy: Where the finding lands.
    ///   - original: The other copy it names.
    ///   - clones: The class, for its size and length.
    ///   - context: Repo-wide state.
    /// - Returns: The finding.
    private func finding(
        at copy: CloneSpan, copying original: CloneSpan, in clones: CloneClass, context: AnalysisContext
    ) -> Finding {
        let count = clones.members.count
        let size = count > 2 ? "\(clones.tokens) tokens, one of \(count) copies" : "\(clones.tokens) tokens"
        let message = "Duplicates lines \(original.start)–\(original.end) of \(original.path) (\(size))."
        return ProjectFinding.make(id, copy.path, copy.start, message, context)
    }
}
