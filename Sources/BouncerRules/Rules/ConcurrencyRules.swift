import Foundation
import BouncerCore

/// Flags a Swift `Task { … }` or `Task.detached { … }` started as a statement, so its handle is dropped and nothing
/// can cancel it, when its body never checks for cancellation.
///
/// Opt-in, since a fire-and-forget task in a button action is often fine. A task counts as fire-and-forget when it
/// starts a statement: at the start of a line, after `{`, `;`, or a closure's `in`, or after `_ =`. A task assigned
/// to a variable or property, returned, or passed as an argument keeps its handle and isn't flagged, and neither is
/// SwiftUI's `.task { }` modifier, which cancels with its view. A task whose body (followed by braces) mentions
/// `isCancelled`, `checkCancellation`, or `withTaskCancellationHandler` is handling cancellation. Test files are
/// skipped.
public struct FireAndForgetTaskRule: Rule {
    public static let ruleID = "fire-and-forget-task"
    public let id = FireAndForgetTaskRule.ruleID
    private static let unstructuredTask = TextMatching.regex(
        #"(?:^|[{;]|\bin)\s*(?:_\s*=\s*)?Task(?:\.detached)?\s*(?:\([^)]*\))?\s*\{"#
    )
    private static let cancellation = TextMatching.regex(#"isCancelled|checkCancellation|withTaskCancellationHandler"#)

    /// Creates the rule.
    public init() {}

    /// Flags each fire-and-forget task whose body never checks for cancellation.
    ///
    /// Runs only when `.bouncer` enables it explicitly.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's settings.
    /// - Returns: One finding per such task.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        guard let settings = SourceText.optInSettings(id, context), file.language == .swift,
              !TextMatching.isTestPath(file.path) else { return [] }
        let message = "Task is started and forgotten, so nothing can cancel it; keep its handle and cancel it, "
            + "or use structured concurrency."
        return SourceText.flagCodeLines(id, settings, file) { index in
            Self.startsForgottenTask(at: index, in: file) ? message : nil
        }
    }

    /// Reports whether a line starts a fire-and-forget task whose body ignores cancellation.
    ///
    /// - Parameters:
    ///   - index: The line's 0-based index.
    ///   - file: The file it's in.
    /// - Returns: Whether the line starts such a task.
    private static func startsForgottenTask(at index: Int, in file: SourceFile) -> Bool {
        guard TextMatching.matches(unstructuredTask, SourceText.code(of: file.lines[index])) else { return false }
        let end = SourceText.blockEnd(from: index, in: file)
        return !file.lines[index...end].contains { TextMatching.matches(cancellation, $0) }
    }
}

/// Flags a Go `go` statement in a function with no visible way to wait for or stop the goroutine: no `context`, no
/// `sync.WaitGroup` or `errgroup`, and no channel.
///
/// It's text-based and conservative: the enclosing top-level `func` (followed by braces) is searched for `ctx`,
/// `context.`, `WaitGroup`, `wg.`, `errgroup`, `chan`, `<-`, `.Wait(`, `.Done(`, `sync.`, `select`, `close(`,
/// `done`, `quit`, `stop`, or `shutdown`; any of them counts as coordination, as does the goroutine's own body
/// mentioning one. Goroutines in test files are checked too.
public struct GoUnmanagedGoroutineRule: Rule {
    public static let ruleID = "go-unmanaged-goroutine"
    public let id = GoUnmanagedGoroutineRule.ruleID
    private static let goStatement = TextMatching.regex(#"(?m)^\s*go\s+(?:func\b|[\w.]+\s*(?:\[[^\]]*\])?\()"#)
    private static let functionStart = TextMatching.regex(#"^func\b"#)
    private static let coordination = TextMatching.regex(
        #"\bctx\b|\bcontext\.|WaitGroup|\bwg\b|errgroup|\bchan\b|<-|\.Wait\(|\.Done\(|\bsync\.|\bselect\s*\{|"#
            + #"\bclose\(|(?i:\bdone\b|\bquit\b|\bstop\w*|shutdown)"#
    )

    /// Creates the rule.
    public init() {}

    /// Flags each `go` statement in a function with nothing to wait for or stop the goroutine.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per unmanaged goroutine.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, file.language == .go, TextMatching.matches(Self.goStatement, file.contents) else {
            return []
        }
        let message = "Goroutine has no context, WaitGroup, or channel to wait for or stop it; it can leak or "
            + "outlive its caller."
        return SourceText.flagCodeLines(id, settings, file) { Self.isUnmanaged(at: $0, in: file) ? message : nil }
    }

    /// Reports whether a line starts a goroutine in a function with no coordination.
    ///
    /// - Parameters:
    ///   - index: The line's 0-based index.
    ///   - file: The file it's in.
    /// - Returns: Whether the line is a `go` statement with nothing to wait for or stop it.
    private static func isUnmanaged(at index: Int, in file: SourceFile) -> Bool {
        guard TextMatching.matches(goStatement, file.lines[index]) else { return false }
        let start = file.lines[...index].lastIndex { TextMatching.matches(functionStart, $0) } ?? index
        let ownBlockEnd = file.lines[index].contains("{") ? SourceText.blockEnd(from: index, in: file) : index
        let end = max(SourceText.blockEnd(from: start, in: file), ownBlockEnd)
        return !file.lines[start...end].contains { TextMatching.matches(coordination, SourceText.code(of: $0)) }
    }
}
