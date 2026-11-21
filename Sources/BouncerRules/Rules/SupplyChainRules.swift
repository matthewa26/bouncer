import Foundation
import BouncerCore

/// Flags a downloaded script piped straight into a shell or interpreter, in shell and PowerShell scripts,
/// Dockerfiles, Makefiles, and YAML (CI workflows): `curl … | sh`, `wget -O- … | sudo bash`,
/// `bash <(curl …)`, `sh -c "$(curl …)"`, `irm … | iex`, and `iex (New-Object Net.WebClient).DownloadString(…)`.
///
/// Markdown and other documentation aren't checked, since install one-liners are what docs show. Comment
/// lines are skipped, and so is a fetch with no concrete source (no `.`, `:`, or `$`), such as `curl <url> | sh`
/// in help text. Downloading to a file and verifying a checksum before running it isn't flagged. Silence a
/// deliberate use with `# bouncer:disable-line pipe-to-shell`.
public struct PipeToShellRule: Rule {
    public let id = "pipe-to-shell"

    private static let extensions: Set = ["sh", "bash", "zsh", "ps1", "psm1", "yml", "yaml", "mk", "dockerfile"]
    private static let names: Set = ["dockerfile", "containerfile", "makefile", "gnumakefile", "justfile"]
    private static let interpreter = #"(sudo\s+(-\S+\s+)*)?(env\s+)?"#
        + #"(sh|bash|zsh|dash|ksh|python[0-9.]*|perl|ruby|node)\b"#
    private static let piped = TextMatching.regex(#"\b(curl|wget)\b([^|]*)\|\s*"# + interpreter)
    private static let substituted = TextMatching.regex(
        #"(\b(bash|sh|zsh|source)\b|(^|\s)\.)\s*(-\S+\s+)*<\(\s*(curl|wget)\b([^)]*)"#
            + #"|\b(bash|sh|zsh)\s+-c\s+["']?\$\(\s*(curl|wget)\b([^)]*)"#
    )
    private static let powerShell = TextMatching.regex(
        #"(?i)\b(iwr|irm|Invoke-WebRequest|Invoke-RestMethod|curl|wget)\b([^|]*)\|\s*(iex|Invoke-Expression)\b"#
            + #"|\b(iex|Invoke-Expression)\b.*(\b(iwr|irm|Invoke-WebRequest|Invoke-RestMethod)\b|\.DownloadString\()"#
    )

    /// Creates the rule.
    public init() {}

    /// Flags each line of a script, Dockerfile, Makefile, or YAML file that pipes a download into a shell.
    ///
    /// - Parameters:
    ///   - file: The file to inspect.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per offending line.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        guard Self.applies(to: file) else { return [] }
        return LineFindings(ruleID: id, settings: context.settings(for: id)).scan(file) { line in
            Self.pipesDownload(line) ? Self.message : nil
        }
    }

    private static let message = "A downloaded script is piped straight into a shell or interpreter; download it "
        + "to a file, verify its checksum or signature, then run it."

    /// Reports whether a file is a script, Dockerfile, Makefile, or YAML file, by name, extension, or a
    /// shell shebang.
    ///
    /// - Parameter file: The file.
    /// - Returns: Whether the rule checks it.
    static func applies(to file: SourceFile) -> Bool {
        let name = file.path.lastPathComponent.lowercased()
        let stem = String(name.prefix { $0 != "." })
        if extensions.contains(file.path.pathExtension.lowercased()) || names.contains(stem) { return true }
        guard let first = file.lines.first, first.hasPrefix("#!") else { return false }
        return ["sh", "bash", "zsh"].contains { first.hasSuffix("/" + $0) || first.hasSuffix(" " + $0) }
    }

    /// Reports whether a non-comment line pipes a download from a concrete source into a shell.
    ///
    /// - Parameter line: The line.
    /// - Returns: Whether it matches one of the download-and-run shapes.
    static func pipesDownload(_ line: Substring) -> Bool {
        guard !line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("#") else { return false }
        let matches = [piped, substituted, powerShell].flatMap { TextMatching.captures($0, line) }
        return matches.contains { $0.first.map(isConcreteSource) ?? false }
    }

    /// Reports whether a matched download names a real source, a URL, host, or variable, rather than a
    /// placeholder such as `<url>`.
    ///
    /// - Parameter text: The matched command.
    /// - Returns: Whether it holds a `.`, `:`, or `$`.
    private static func isConcreteSource(_ text: String) -> Bool {
        text.contains { ".:$".contains($0) }
    }
}

/// Flags a GitHub Actions `uses:` reference that isn't pinned to a full commit SHA, in workflows
/// (`.github/workflows/*.yml`) and action definitions (`action.yml`). Off unless configured; its default
/// severity once enabled is `info`.
///
/// A tag or branch can be moved to point at different code, so `actions/checkout@v4` runs whatever the tag
/// names today. Local actions (`./…`) and Docker images pinned by digest (`docker://…@sha256:…`) are fine.
public struct UnpinnedCIActionRule: Rule {
    public let id = "unpinned-ci-action"

    private static let uses = TextMatching.regex(#"^\s*(-\s+)?uses:\s*["']?([^\s"'#]+)"#)
    private static let commit = TextMatching.regex(#"^[0-9a-fA-F]{40}$"#)

    /// Creates the rule.
    public init() {}

    /// Flags each `uses:` line whose action isn't pinned to a commit.
    ///
    /// - Parameters:
    ///   - file: The file to inspect.
    ///   - context: Repo-wide state; the rule only runs when configured.
    /// - Returns: One finding per unpinned reference.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        guard let settings = context.ruleSettings[id], Self.isWorkflow(file.path) else { return [] }
        return LineFindings(ruleID: id, settings: settings).scan(file) { line in
            TextMatching.captures(Self.uses, line).first?.last.flatMap(Self.problem(with:))
        }
    }

    /// Reports whether a file is a GitHub Actions workflow or action definition.
    ///
    /// - Parameter path: The file's location.
    /// - Returns: Whether the rule checks it.
    static func isWorkflow(_ path: URL) -> Bool {
        let name = path.lastPathComponent, ext = path.pathExtension.lowercased()
        guard ext == "yml" || ext == "yaml" else { return false }
        let folders = path.deletingLastPathComponent().pathComponents.suffix(2)
        return name.hasPrefix("action.") || folders == [".github", "workflows"]
    }

    /// Explains what's wrong with one `uses:` reference.
    ///
    /// - Parameter reference: The reference as written, such as `actions/checkout@v4`.
    /// - Returns: The message, or `nil` for a local action or one pinned to a commit or digest.
    static func problem(with reference: String) -> String? {
        if reference.hasPrefix("./") || reference.hasPrefix("../") { return nil }
        if reference.hasPrefix("docker://") { return dockerProblem(with: reference) }
        let parts = reference.split(separator: "@", maxSplits: 1).map(String.init)
        if parts.count == 2, TextMatching.matches(commit, parts[1]) { return nil }
        let ref = parts.count == 2 ? "\"\(parts[1])\", which can be moved" : "no ref"
        return "Action \"\(parts[0])\" is referenced by \(ref); pin it to a full 40-character commit SHA "
            + "and keep the version in a comment."
    }

    /// Explains what's wrong with a Docker image action.
    ///
    /// - Parameter reference: The `docker://` reference.
    /// - Returns: The message, or `nil` for an image pinned by digest.
    private static func dockerProblem(with reference: String) -> String? {
        guard !reference.contains("@sha256:") else { return nil }
        return "Docker action \"\(reference)\" isn't pinned to a digest; reference it as "
            + "docker://image@sha256:<digest>."
    }
}

/// Builds a rule's findings line by line, once its settings are resolved.
struct LineFindings {
    let ruleID: String
    let settings: RuleSettings

    /// Reports each line a check explains, when the rule is enabled.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - explain: Returns the message for a line that has a problem, or `nil`.
    /// - Returns: One finding per explained line.
    func scan(_ file: SourceFile, explain: (Substring) -> String?) -> [Finding] {
        guard settings.enabled else { return [] }
        return file.lines.enumerated().compactMap { index, line in
            explain(line).map {
                Finding(ruleID: ruleID, severity: settings.severity, filePath: file.path, line: index + 1, message: $0)
            }
        }
    }
}
