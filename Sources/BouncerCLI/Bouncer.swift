import ArgumentParser

/// Bouncer: a configurable, multi-language coding-standards and code-smell checker.
@main
struct Bouncer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bouncer",
        abstract: "Enforces coding standards, detects code smells, and checks coverage thresholds.",
        version: GeneratedVersion.versionString,
        subcommands: [Check.self, Review.self, Configure.self, BaselineCommand.self],
        defaultSubcommand: Check.self
    )
}
