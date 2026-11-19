import Foundation
import BouncerCore
import BouncerGit

/// Flags a function that was already over the complexity or length limit on the base branch and got
/// worse, so code over the limit (baselined, say) can only improve.
///
/// The base is the merge base of `HEAD` and `base` (by default the first of `origin/main`, `main`,
/// `origin/master`, and `master` that exists); without one the rule does nothing. Each checked file is
/// measured as it is now and as it was at the base, and functions are matched by name; a name declared a
/// different number of times in the two versions, a new function, and a renamed one are skipped, and so is
/// a function crossing a limit, since `cyclomatic-complexity` and `long-function` already report those.
/// The limits default to those two rules' `max` and `maxLines`.
public struct ComplexityRatchetRule: Sendable {
    public let id = "complexity-ratchet"
    static let defaultBases = ["origin/main", "main", "origin/master", "master"]
    private let measurer: FunctionMeasuring

    /// Creates the rule.
    ///
    /// - Parameter measurer: Measures each version's functions.
    public init(measurer: FunctionMeasuring) {
        self.measurer = measurer
    }

    /// Compares each checked file with its base version.
    ///
    /// - Parameters:
    ///   - files: The files being checked.
    ///   - source: Resolves the base and reads files there.
    ///   - context: Repo-wide state, with `base`, `maxComplexity`, and `maxLines`.
    /// - Returns: One finding per function that got worse while over a limit.
    public func evaluate(_ files: [SourceFile], source: ChangeSource, context: AnalysisContext) -> [Finding] {
        guard !files.isEmpty, let base = resolveBase(source: source, context: context) else { return [] }
        let limits = RatchetLimits(context: context, ruleID: id)
        return files.flatMap { findings(in: $0, base: base, limits: limits, source: source, context: context) }
    }

    /// Compares one file with its base version.
    ///
    /// - Parameters:
    ///   - file: The file as it is now.
    ///   - base: The base ref and commit.
    ///   - limits: The limits a function must already exceed.
    ///   - source: Reads the base version.
    ///   - context: Repo-wide state.
    /// - Returns: One finding per function that got worse while over a limit.
    private func findings(
        in file: SourceFile, base: (ref: String, commit: String), limits: RatchetLimits, source: ChangeSource,
        context: AnalysisContext
    ) -> [Finding] {
        let path = RepoPath.relative(file.path, to: context.repoRoot)
        return pairs(in: file, base: base, source: source, context: context).compactMap { pair in
            message(pair.old, pair.new, base: base, limits: limits).map {
                ProjectFinding.make(id, path, pair.new.line, $0, context)
            }
        }
    }

    /// Finds the base commit: the merge base with `base`, or with the first default branch that exists.
    ///
    /// - Parameters:
    ///   - source: Resolves refs.
    ///   - context: Repo-wide state, with `base`.
    /// - Returns: The ref used and the merge base, or `nil` if none resolves.
    private func resolveBase(source: ChangeSource, context: AnalysisContext) -> (ref: String, commit: String)? {
        let configured = context.settings(for: id).parameters.string("base", default: "")
        return source.mergeBase(of: configured.isEmpty ? Self.defaultBases : [configured], in: context.repoRoot)
    }

    /// Pairs a file's functions now with the same functions at the base.
    ///
    /// - Parameters:
    ///   - file: The file as it is now.
    ///   - base: The base ref and commit.
    ///   - source: Reads the base version.
    ///   - context: Repo-wide state, for the repo root.
    /// - Returns: The matched pairs, or none if the file is new or isn't measured.
    private func pairs(
        in file: SourceFile, base: (ref: String, commit: String), source: ChangeSource, context: AnalysisContext
    ) -> [(old: FunctionMeasure, new: FunctionMeasure)] {
        let path = RepoPath.relative(file.path, to: context.repoRoot)
        guard let now = measurer.functions(in: file),
              let contents = source.contents(of: path, at: base.commit, in: context.repoRoot) else { return [] }
        let old = SourceFile(path: file.path, language: file.language, contents: contents)
        guard let before = measurer.functions(in: old) else { return [] }
        return FunctionMatcher.pairs(before: before, after: now)
    }

    /// Describes how a function got worse while over a limit.
    ///
    /// - Parameters:
    ///   - old: The function at the base.
    ///   - new: The function now.
    ///   - base: The base ref and commit.
    ///   - limits: The limits.
    /// - Returns: The message, or `nil` if it didn't get worse past a limit.
    private func message(
        _ old: FunctionMeasure, _ new: FunctionMeasure, base: (ref: String, commit: String), limits: RatchetLimits
    ) -> String? {
        let worse = limits.regressions(from: old, to: new)
        guard !worse.isEmpty, let name = new.name else { return nil }
        return "Function \"\(name)\" got worse than at \(base.ref) (\(base.commit.prefix(7))): "
            + worse.joined(separator: "; ") + "."
    }
}

/// The limits a function must already exceed for `complexity-ratchet` to report it getting worse.
struct RatchetLimits {
    let complexity: Int
    let lines: Int

    /// Reads the limits: the rule's own parameters, else `cyclomatic-complexity`'s and `long-function`'s.
    ///
    /// - Parameters:
    ///   - context: Repo-wide state.
    ///   - ruleID: The ratchet rule's ID.
    init(context: AnalysisContext, ruleID: String) {
        let own = context.settings(for: ruleID).parameters
        let complexity = context.settings(for: AnalyzerFunctionMeasurer.complexityRule).parameters
            .int("max", default: 10)
        let lines = context.settings(for: AnalyzerFunctionMeasurer.lengthRule).parameters
            .int("maxLines", default: 40)
        self.complexity = own.int("maxComplexity", default: complexity)
        self.lines = own.int("maxLines", default: lines)
    }

    /// Describes how a function already over a limit at the base got worse.
    ///
    /// Crossing a limit isn't reported here: `cyclomatic-complexity` and `long-function` already flag it.
    ///
    /// - Parameters:
    ///   - old: The function at the base.
    ///   - new: The function now.
    /// - Returns: One phrase per measurement that was over its limit and grew; empty if none.
    func regressions(from old: FunctionMeasure, to new: FunctionMeasure) -> [String] {
        var result: [String] = []
        if new.complexity > old.complexity, old.complexity > complexity {
            result.append("complexity \(old.complexity) → \(new.complexity), over the \(complexity) limit")
        }
        if let before = old.logicalLines, let after = new.logicalLines, after > before, before > lines {
            result.append("\(before) → \(after) logical lines, over the \(lines)-line limit")
        }
        return result
    }
}

/// Matches functions between two versions of a file by name.
enum FunctionMatcher {
    /// Pairs functions with the same name, in order, for each name declared equally often in both versions.
    ///
    /// - Parameters:
    ///   - before: The old version's functions.
    ///   - after: The new version's functions.
    /// - Returns: The pairs; unnamed, anonymous, new, removed, and ambiguous functions are left out.
    static func pairs(
        before: [FunctionMeasure], after: [FunctionMeasure]
    ) -> [(old: FunctionMeasure, new: FunctionMeasure)] {
        let old = byName(before), new = byName(after)
        return new.keys.sorted().flatMap { name -> [(old: FunctionMeasure, new: FunctionMeasure)] in
            guard let was = old[name], let now = new[name], was.count == now.count else { return [] }
            return Array(zip(was, now)).map { (old: $0.0, new: $0.1) }
        }
    }

    /// Groups named functions by name, in line order.
    ///
    /// - Parameter functions: The functions.
    /// - Returns: Each name's functions.
    private static func byName(_ functions: [FunctionMeasure]) -> [String: [FunctionMeasure]] {
        let named = functions.filter { $0.name != nil && $0.name != "<anonymous>" }
        return Dictionary(grouping: named.sorted { $0.line < $1.line }) { $0.name ?? "" }
    }
}
