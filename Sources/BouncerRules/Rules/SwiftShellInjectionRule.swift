import Foundation
import BouncerCore

/// Flags a Swift `Process`/`NSTask` that runs a shell with `-c` and an interpolated command string, such as
/// `process.arguments = ["-c", "git log \(ref)"]` with `/bin/sh` as the executable.
///
/// It's text-based: the file must mention `Process` or `NSTask`, and the element right after `"-c"` (on the same
/// line or up to three lines below) must be a string literal containing `\(…)`. The shell is found either in that
/// argument list (`["sh", "-c", …]`, for `/usr/bin/env`) or as the nearest `executableURL`/`launchPath`/
/// `fileURLWithPath:` path within 15 lines above or 5 below; when no executable is named nearby, any `/bin/sh`-style
/// path in the file counts. A command assembled into a variable first (`["-c", command]`) isn't followed.
public struct SwiftShellInjectionRule: Rule {
    public static let ruleID = "swift-shell-injection"
    public let id = SwiftShellInjectionRule.ruleID
    private static let processType = TextMatching.regex(#"\b(Process|NSTask)\b"#)
    private static let shellPath = TextMatching.regex(#""(/usr)?/bin/(ba|z|da|k)?sh""#)
    private static let shellName = TextMatching.regex(#""((/usr)?/bin/)?(ba|z|da|k)?sh"\s*,\s*$"#)
    private static let executable = TextMatching.regex(#"(executableURL|launchPath|fileURLWithPath:)[^"]*"([^"]+)""#)
    private static let interpolatedNext = TextMatching.regex(##"^\s*,\s*#*"[^"]*\\#*\("##)
    private static let lookahead = 3
    private static let executableWindow = (above: 15, below: 5)

    /// Creates the rule.
    public init() {}

    /// Flags each `"-c"` argument followed by an interpolated command string passed to a shell.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per interpolated shell command.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, file.language == .swift, TextMatching.matches(Self.processType, file.contents)
        else { return [] }
        let message = "Shell command built by interpolation risks injection; run the program directly with arguments."
        return file.lines.indices.filter { Self.isShellCommand(at: $0, in: file) }
            .map { index in
                Finding(ruleID: id, severity: settings.severity, filePath: file.path, line: index + 1, message: message)
            }
    }

    /// Reports whether the line at `index` passes `"-c"` and an interpolated string to a shell.
    ///
    /// - Parameters:
    ///   - index: The candidate line's 0-based index.
    ///   - file: The file it's in.
    /// - Returns: Whether the line is an interpolated shell command.
    private static func isShellCommand(at index: Int, in file: SourceFile) -> Bool {
        let line = file.lines[index]
        guard !line.drop(while: \.isWhitespace).hasPrefix("//"), let flag = line.range(of: #""-c""#),
              isInterpolated(after: flag.upperBound, at: index, in: file) else { return false }
        if TextMatching.matches(shellName, line[..<flag.lowerBound]) { return true }
        let path = nearestExecutable(to: index, in: file).map { "\"\($0)\"" }
        return TextMatching.matches(shellPath, path ?? file.contents)
    }

    /// Reports whether the argument after `"-c"` is a string literal with interpolation.
    ///
    /// - Parameters:
    ///   - position: Where `"-c"` ends on its line.
    ///   - index: The line's 0-based index.
    ///   - file: The file it's in.
    /// - Returns: Whether the next element, on this line or the few below, contains `\(…)`.
    private static func isInterpolated(after position: String.Index, at index: Int, in file: SourceFile) -> Bool {
        let following = file.lines[(index + 1)..<min(file.lines.count, index + 1 + lookahead)]
        let segments = [file.lines[index][position...]] + following
        let rest = segments.map { segment in
            String(segment).replacingOccurrences(of: #"//[^"]*$"#, with: "", options: .regularExpression)
        }
        return TextMatching.matches(interpolatedNext, rest.joined(separator: " "))
    }

    /// Finds the executable path named closest to a line, as the process the arguments most likely belong to.
    ///
    /// - Parameters:
    ///   - index: The arguments line's 0-based index.
    ///   - file: The file it's in.
    /// - Returns: The nearest executable path, or `nil` if none is named within the window.
    private static func nearestExecutable(to index: Int, in file: SourceFile) -> String? {
        let window = max(0, index - executableWindow.above)...min(file.lines.count - 1, index + executableWindow.below)
        let named = window.compactMap { line in
            TextMatching.captures(executable, file.lines[line]).first.map { (abs(line - index), $0[2]) }
        }
        return named.min { $0.0 < $1.0 }?.1
    }
}
