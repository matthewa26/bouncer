import Foundation
import BouncerCore

/// Size rules over whole types and closures, and the file-name rule.
extension DeclarationFindings {
    private static let fileNameLanguages: Set<Language> = [.swift, .typescript, .javascript]
    private static let conventionalFileNames: Set<String> = ["main", "index", "package", "mod"]
    private static let roleSuffixes: Set<String> = ["d", "test", "spec", "stories"]

    /// Runs the type-size, closure-size, file-name, and type-aware naming rules.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including each rule's resolved settings.
    /// - Returns: The combined findings.
    static func shapeFindings(_ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext) -> [Finding] {
        largeTypes(summary, file: file, context: context)
            + longClosures(summary, file: file, context: context)
            + fileNameMismatch(summary, file: file, context: context)
            + typedNameFindings(summary, file: file, context: context)
    }

    /// Flags every type whose declaration spans more logical lines than `maxLines`.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per over-long type.
    private static func largeTypes(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: "large-type")
        guard settings.enabled else { return [] }
        let maxLines = settings.parameters.int("maxLines", default: 400)
        return summary.shapes.types.compactMap { type in
            let count = logicalLines(in: file, from: type.startLine, to: type.endLine)
            guard count > maxLines else { return nil }
            let message = "Type \"\(type.name)\" has \(count) logical lines, over the \(maxLines)-line limit."
            return finding("large-type", type.startLine, message, settings.severity, file)
        }
    }

    /// Flags every closure longer than `maxLines`, skipping one nested in a closure that's already flagged.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per outermost over-long closure.
    private static func longClosures(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: "long-closure")
        guard settings.enabled else { return [] }
        let maxLines = settings.parameters.int("maxLines", default: 20)
        let long = summary.shapes.closures.map { ($0, logicalLines(in: file, from: $0.startLine, to: $0.endLine)) }
            .filter { $0.1 > maxLines }
        return long.filter { inner in !long.contains { encloses($0.0, inner.0) } }.map { closure, count in
            let message = "Closure has \(count) logical lines, over the \(maxLines)-line limit; name it as a function."
            return finding("long-closure", closure.startLine, message, settings.severity, file)
        }
    }

    /// Reports whether one closure strictly contains another.
    ///
    /// - Parameters:
    ///   - outer: The possibly enclosing closure.
    ///   - inner: The possibly enclosed closure.
    /// - Returns: Whether `outer` spans `inner` and isn't the same extent.
    private static func encloses(_ outer: CollectedClosure, _ inner: CollectedClosure) -> Bool {
        outer != inner && outer.startLine <= inner.startLine && inner.endLine <= outer.endLine
    }

    /// Counts the logical lines in a 1-indexed, inclusive line span.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - start: The span's first line.
    ///   - end: The span's last line.
    /// - Returns: The non-blank, non-comment lines in the span.
    private static func logicalLines(in file: SourceFile, from start: Int, to end: Int) -> Int {
        let profile = LanguageProfile(lineCommentPrefixes: commentPrefixes(for: file.language))
        return LogicalLineCounter.count(in: file, range: (start - 1)...max(start - 1, end - 1), profile: profile)
    }

    /// Flags a file whose one primary type is named differently from the file.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: A single finding, or none.
    private static func fileNameMismatch(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: "file-name-mismatch")
        let base = file.path.deletingPathExtension().lastPathComponent
        guard settings.enabled, fileNameLanguages.contains(file.language), isNamedForItsContents(base),
              let primary = primaryType(of: summary.shapes), !fileName(base, matches: primary.name) else { return [] }
        let message = "File \"\(file.path.lastPathComponent)\" holds only \"\(primary.name)\"; "
            + "name the file after it."
        return [finding("file-name-mismatch", primary.startLine, message, settings.severity, file)]
    }

    /// Reports whether a file name is expected to name its type: not an entry point like `main` or
    /// `index`, and not a TS/JS declaration, test, or story file like `tree.test` or `dsl.d`.
    ///
    /// - Parameter base: The file name without its extension.
    /// - Returns: Whether the rule applies to the file.
    private static func isNamedForItsContents(_ base: String) -> Bool {
        let parts = base.lowercased().split(separator: ".").map(String.init)
        guard let first = parts.first, !conventionalFileNames.contains(first) else { return false }
        return parts.count == 1 || !roleSuffixes.contains(parts.last ?? "")
    }

    /// Picks a file's primary type: its only top-level type other files can see, when nothing else
    /// visible (a function, a variable, an extension of another type) shares the file.
    ///
    /// - Parameter shapes: The file's shape facts.
    /// - Returns: The primary type, or `nil` if the file has none or several.
    private static func primaryType(of shapes: ShapeFacts) -> DeclaredType? {
        let visible = shapes.types.filter { $0.isTopLevel && $0.visibility != .private }
        guard visible.count == 1, let primary = visible.first else { return nil }
        return shapes.topLevelOthers.allSatisfy { $0 == primary.name } ? primary : nil
    }

    /// Reports whether a file name matches a type name, ignoring case and `-`, `_`, `.` separators, a
    /// `Test`/`Tests` suffix, and a TS `I` interface prefix; either side of a Swift `Type+Extension`
    /// name, or the part before a `.` (`Formatter.step1`), may match, and the type may contain the
    /// file's name, as `ColorOptions` in `Color.swift` does.
    ///
    /// - Parameters:
    ///   - base: The file name without its extension.
    ///   - typeName: The primary type's name.
    /// - Returns: Whether they match.
    private static func fileName(_ base: String, matches typeName: String) -> Bool {
        let parts = base.split(separator: "+") + base.split(separator: ".").prefix(1)
        let files = ([base] + parts.map(String.init)).map(squashed)
        let unprefixed = typeName.dropFirst()
        let isInterface = typeName.hasPrefix("I") && unprefixed.first?.isUppercase == true
        let types = ([typeName] + (isInterface ? [String(unprefixed)] : [])).map(squashed)
        return files.contains { file in types.contains { $0.contains(file) || file.hasPrefix($0) } }
    }

    /// Lowercases a name, drops everything but letters and digits, and drops a `test`/`tests` suffix.
    ///
    /// - Parameter name: The name.
    /// - Returns: The squashed name, so `user-service`, `user_service`, and `UserService` compare equal.
    private static func squashed(_ name: String) -> String {
        let letters = String(name.lowercased().filter { $0.isLetter || $0.isNumber })
        let suffix = ["tests", "test"].first { letters.hasSuffix($0) && letters.count > $0.count }
        return suffix.map { String(letters.dropLast($0.count)) } ?? letters
    }
}
