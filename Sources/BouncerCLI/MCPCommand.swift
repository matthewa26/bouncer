import ArgumentParser
import Foundation
import BouncerGit
import BouncerMCP

/// Serves Bouncer to a coding agent over the Model Context Protocol on standard input and output.
///
/// The server runs one analysis, keeps the result in memory, and answers drill-downs from it. Nothing but the
/// protocol is written to standard output: no update check, progress display, prompt, or hook runs.
struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp", abstract: "Serve analysis results to a coding agent over MCP (stdio)."
    )

    /// How the server teaches an agent the loop.
    private static let instructions = """
        Bouncer checks code quality. Loop: scan (then status until it finishes) -> next_batch (the one file \
        and rule to fix next, with code) -> edit the code -> verify the files you edited -> repeat. findings \
        lists any slice (filter by rule, path, or severity; page with cursor). explain_rule says how to fix a \
        rule's findings; check runs the pre-commit check on the staged diff.
        """

    @Argument(help: "The directory to scan by default.")
    var path: String = "."

    @Option(help: "Apply a bundled preset, such as kirby, as the base config layer.")
    var profile: String?

    @Option(help: "An explicit .bouncer path, overriding the layered config resolution.")
    var config: String?

    @Flag(help: "Log tool calls and scan notes to standard error.")
    var verbose = false

    /// Serves until standard input closes.
    func run() async throws {
        let session = MCPSession(defaults: defaults())
        let version = GeneratedVersion.versionString
        let info = MCPServerInfo(name: "bouncer", version: version, instructions: Self.instructions)
        await MCPServer(info: info, handler: BouncerTools(session: session)).serveStandardIO()
    }

    /// What the session starts with: the repository containing `path`, and the config flags.
    ///
    /// - Returns: The defaults.
    private func defaults() -> MCPSessionDefaults {
        let directory = URL(fileURLWithPath: path).absoluteURL.standardizedFileURL
        let repoRoot = GitRepoLocator.repoRoot(startingAt: directory) ?? directory
        let log = MCPLog(verbose: verbose)
        return MCPSessionDefaults(
            repoRoot: repoRoot, rootDirectory: directory, profile: profile, configPath: config, log: log
        )
    }
}
