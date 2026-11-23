import Foundation
import BouncerCore

extension FindingSelection {
    /// Keeps the findings that pass the rule, path, and severity filters, in the order given, ignoring the page.
    ///
    /// Unlike `apply(to:repoRoot:)`, it doesn't sort, so a caller that keeps findings in page order, such as
    /// `bouncer mcp`, sorts once and filters that order on every call.
    ///
    /// - Parameters:
    ///   - findings: The findings, in the order to keep.
    ///   - repoRoot: The repository root, which `paths` globs are relative to.
    /// - Returns: The findings that pass.
    public func filtering(_ findings: [Finding], repoRoot: URL) -> [Finding] {
        let rules = Set(rules), minimum = minimumSeverity ?? .info
        var answers: [String: Bool] = [:]
        return findings.filter { finding in
            guard rules.isEmpty || rules.contains(finding.ruleID), finding.severity >= minimum else { return false }
            guard !paths.isEmpty else { return true }
            return matchesPaths(finding.filePath, repoRoot: repoRoot, answers: &answers)
        }
    }

    /// Whether a file matches any `paths` glob, remembering each file's answer.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - repoRoot: The repository root.
    ///   - answers: Each file's answer so far, by full path.
    /// - Returns: Whether a glob matches the file's path relative to the root.
    private func matchesPaths(_ file: URL, repoRoot: URL, answers: inout [String: Bool]) -> Bool {
        if let answer = answers[file.path] { return answer }
        let relative = RepoPath.relative(file, to: repoRoot)
        let answer = paths.contains { GlobMatcher.matches(path: relative, pattern: $0) }
        answers[file.path] = answer
        return answer
    }
}
